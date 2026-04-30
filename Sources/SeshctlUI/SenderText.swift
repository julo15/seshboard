import SwiftUI
import AppKit

// Coverage policy:
// - chooseTruncation: pure helper, must clear 60% line coverage
// - widthBudgetToCharBudget: measurement adapter, exempt — text metrics
//   are environmental and non-deterministic across machines/CI
// - SenderText body: SwiftUI view, exempt per AGENTS.md

/// Layout constants for the line-1 sender column. Centralized so a future
/// width-tuning pass touches one place; the row views consume `width`
/// rather than spelling out a literal.
enum SenderColumnLayout {
    /// Fixed sender-column width (pt). Plan-documented starting point — to
    /// be tuned against real session-DB repo-name distribution post-Phase-1
    /// soak. See `.agents/plans/2026-04-29-1730-row-ui-gmail-redesign.md`
    /// (R1, "Sender column width" deferred question).
    static let width: CGFloat = 180

    /// Sender / branch font size. The column uses a monospace face, so bold
    /// alone doesn't widen glyphs the way it does in proportional faces — to
    /// mimic the "unread reads bigger" effect Gmail gets for free, bump the
    /// size 1pt on unread rows. Read rows match `.body` on macOS.
    static func textSize(isUnread: Bool) -> CGFloat {
        isUnread ? 14 : 13
    }
}

/// Result of `chooseTruncation`. Describes what the rendering layer should
/// paint for the repo part and (optional) suffix part. The two parts are
/// styled separately, so they're returned separately rather than as a single
/// pre-joined string. The renderer is responsible for inserting the ` · `
/// separator between them when `displayedSuffix` is non-nil.
///
/// The embedded ellipsis character (`…`) is included in the strings when
/// truncation has been applied; callers do not need to decide where it goes.
struct TruncationResult: Equatable {
    /// String to render in the primary (repo) style. May be empty when the
    /// caller has no repo budget at all (degenerate / suffix-only fallback).
    let displayedRepo: String

    /// String to render in the secondary/tertiary (suffix) style, or `nil`
    /// when the input had no suffix (or all budget was spent on the repo).
    let displayedSuffix: String?
}

/// Pure char-budget truncation helper. Inputs are character counts, not pixel
/// widths, so this is fully deterministic and table-testable. The view layer
/// composes this with `widthBudgetToCharBudget` to bridge from `GeometryReader`
/// pixels to character budgets.
///
/// Strategy:
/// 1. If the full string (`repoPart` plus ` · suffix` when suffix is non-nil)
///    fits inside the combined budget, return both parts as-is.
/// 2. Otherwise, when there's no suffix, tail-truncate the repo to fit the
///    repo budget (mirrors stock `.truncationMode(.tail)`).
/// 3. Otherwise, when the suffix alone exceeds its budget, fall back to
///    suffix-only with the suffix tail-truncated; the repo is dropped (or
///    replaced with a single `…` when there's room for it).
/// 4. Otherwise, middle-ellipsize the repo to a width-derived budget while
///    preserving the suffix in full. The effective repo budget reclaims any
///    suffix budget the (short) suffix didn't use.
///
/// Char-budget edge cases (zero budgets, empty inputs) are handled without
/// crashing; tests pin down the contract.
func chooseTruncation(
    repoPart: String,
    dirSuffix: String?,
    repoBudgetChars: Int,
    suffixBudgetChars: Int
) -> TruncationResult {
    let repoBudget = max(0, repoBudgetChars)
    let suffixBudget = max(0, suffixBudgetChars)
    let totalBudget = repoBudget + suffixBudget

    // Normalize empty suffix to nil so the renderer doesn't draw a stray
    // separator for `dirSuffix == ""`.
    let suffix: String? = {
        guard let dirSuffix, !dirSuffix.isEmpty else { return nil }
        return dirSuffix
    }()

    // Separator length (` · ` is three Unicode scalars; we count it as the
    // visual char count the user sees on the row).
    let separatorChars = 3

    // Empty inputs — return empty without crashing.
    if repoPart.isEmpty && suffix == nil {
        return TruncationResult(displayedRepo: "", displayedSuffix: nil)
    }

    // Step 1: does the full string fit in the combined budget?
    let naturalLength: Int = {
        if let suffix {
            return repoPart.count + separatorChars + suffix.count
        } else {
            return repoPart.count
        }
    }()

    if naturalLength <= totalBudget {
        return TruncationResult(displayedRepo: repoPart, displayedSuffix: suffix)
    }

    // Step 2: no suffix → tail-truncate the repo to the full combined
    // budget. The 60/40 split only matters when there's a suffix to
    // preserve; with no suffix the repo gets the whole column.
    guard let suffix else {
        return TruncationResult(
            displayedRepo: tailTruncate(repoPart, toBudget: totalBudget),
            displayedSuffix: nil
        )
    }

    // Step 3: degenerate — suffix alone won't fit in its budget. Drop the
    // repo (or replace with `…` when there's room) and tail-truncate the
    // suffix to the total available budget minus separator/ellipsis costs.
    if suffix.count > suffixBudget {
        // Reserve room for "… · " (ellipsis-as-repo + separator) when we
        // have at least 1 + separator chars left for the suffix; otherwise
        // drop the repo entirely and give the whole budget to the suffix.
        let prefixCost = 1 + separatorChars  // "…" + " · "
        if totalBudget > prefixCost {
            let suffixRoom = totalBudget - prefixCost
            return TruncationResult(
                displayedRepo: "…",
                displayedSuffix: tailTruncate(suffix, toBudget: suffixRoom)
            )
        } else {
            return TruncationResult(
                displayedRepo: "",
                displayedSuffix: tailTruncate(suffix, toBudget: totalBudget)
            )
        }
    }

    // Step 4: middle-ellipsize the repo, preserving the suffix in full.
    // Reclaim any suffix budget the (short) suffix didn't use, since the
    // renderer paints them on the same horizontal line.
    let suffixActualCost = suffix.count + separatorChars
    let effectiveRepoBudget = max(0, totalBudget - suffixActualCost)

    return TruncationResult(
        displayedRepo: middleEllipsize(repoPart, toBudget: effectiveRepoBudget),
        displayedSuffix: suffix
    )
}

/// Tail-truncate `s` to fit within `budget` characters. When truncation is
/// required, replaces the trailing characters with `…` (counting toward the
/// budget). When `budget == 0`, returns `""`. When `budget == 1` and
/// truncation is required, returns just `"…"`.
private func tailTruncate(_ s: String, toBudget budget: Int) -> String {
    if budget <= 0 { return "" }
    if s.count <= budget { return s }
    if budget == 1 { return "…" }
    let keep = budget - 1
    let prefix = s.prefix(keep)
    return String(prefix) + "…"
}

/// Middle-ellipsize `s` to fit exactly `budget` characters. Keeps the first
/// `(budget - 1) / 2` characters and the last `budget - 1 - (budget - 1) / 2`
/// characters with a `…` in between. When `budget == 0`, returns `""`. When
/// `budget == 1`, returns `"…"`. When the input already fits, returned as-is.
///
/// Example: `"compound-engineering"` (20 chars) at budget 13 → `"compou…eering"`
/// (first 6, ellipsis, last 6 = 13 total).
private func middleEllipsize(_ s: String, toBudget budget: Int) -> String {
    if budget <= 0 { return "" }
    if s.count <= budget { return s }
    if budget == 1 { return "…" }
    let interior = budget - 1
    let head = interior / 2
    let tail = interior - head
    let headPart = s.prefix(head)
    let tailPart = s.suffix(tail)
    return String(headPart) + "…" + String(tailPart)
}

/// Convert an available pixel width into per-segment character budgets for
/// the pure `chooseTruncation` helper. Smoke-tested only — text metrics are
/// environmental and non-deterministic across machines, so this adapter is
/// exempt from the 60% coverage bar.
///
/// Allocates roughly 60% of available width to the repo budget and 40% to
/// the suffix budget. `chooseTruncation` reclaims unused suffix budget when
/// the suffix is short, so a 60/40 starting split degrades gracefully.
func widthBudgetToCharBudget(
    availableWidth: CGFloat,
    font: NSFont
) -> (repoBudget: Int, suffixBudget: Int) {
    // Measure a representative single-character width using NSString — the
    // method lives on NSString, not NSAttributedString.
    let probe = "M" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let charWidth = probe.size(withAttributes: attributes).width
    guard charWidth > 0 else { return (repoBudget: 0, suffixBudget: 0) }

    let totalChars = max(0, Int((availableWidth / charWidth).rounded(.down)))
    let repoBudget = Int((Double(totalChars) * 0.6).rounded(.down))
    let suffixBudget = totalChars - repoBudget
    return (repoBudget: repoBudget, suffixBudget: suffixBudget)
}

/// Renders a `repo · suffix` sender string with middle-truncation that
/// preserves the disambiguating dir suffix in full. Stock SwiftUI cannot do
/// this — `.truncationMode(.middle)` ellipsizes character-wise, ignoring
/// the logical separator.
///
/// The repo part renders in the primary style; the suffix part renders in
/// `.tertiary` color at the same metric size, per R6 ("lower-contrast color
/// at the same size").
struct SenderText: View {
    let display: SenderDisplay
    /// When true, render at the bumped unread size (see
    /// `SenderColumnLayout.textSize(isUnread:)`). Bold weight is applied by
    /// the parent VStack — this only adjusts size.
    var isUnread: Bool = false
    var font: NSFont {
        NSFont.monospacedSystemFont(
            ofSize: SenderColumnLayout.textSize(isUnread: isUnread),
            weight: isUnread ? .semibold : .regular
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let budgets = widthBudgetToCharBudget(
                availableWidth: proxy.size.width,
                font: font
            )
            let result = chooseTruncation(
                repoPart: display.repoPart,
                dirSuffix: display.dirSuffix,
                repoBudgetChars: budgets.repoBudget,
                suffixBudgetChars: budgets.suffixBudget
            )

            let size = SenderColumnLayout.textSize(isUnread: isUnread)
            HStack(spacing: 0) {
                Text(result.displayedRepo)
                    .font(.system(size: size, design: .monospaced))
                if let suffix = result.displayedSuffix {
                    // Suppress the separator when the repo collapsed to
                    // empty (very narrow widths in step 4); otherwise the
                    // row would render a stray leading ` · suffix`.
                    if !result.displayedRepo.isEmpty {
                        Text(" · ")
                            .font(.system(size: size, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(suffix)
                        .font(.system(size: size, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        }
    }
}
