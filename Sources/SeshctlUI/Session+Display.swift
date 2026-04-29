import Foundation
import SeshctlCore

struct SessionAgeDisplay {
    let timestamp: Date
    let now: Date
    let calendar: Calendar
    let locale: Locale

    init(
        timestamp: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.timestamp = timestamp
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    /// Human-readable timestamp string for the row's right-side time slot.
    /// Mirrors Gmail's idiom with one extension at the recent end —
    /// recent rows get a compact relative label so quick triage doesn't
    /// require parsing a clock time:
    ///
    /// - Less than 1 hour ago (past) → relative (`"30s"`, `"59m"`).
    /// - At least 1 hour ago (past), same calendar day → time of day
    ///   (`"1:22 PM"` in 12h locale, `"13:22"` in 24h locale).
    /// - Different day, same calendar year → abbreviated month + day
    ///   (`"Apr 28"`).
    /// - Different year → abbreviated month + day + year (`"Apr 28, 2025"`).
    ///
    /// Future timestamps (clock skew, or scheduled work) skip the
    /// relative branch entirely and fall through to the calendar-day
    /// absolute formatting — a future-tomorrow timestamp reads as
    /// `"Apr 16"`, not `"0s"`. The locale-aware branches respect the
    /// configured `locale` and `calendar`, so tests can pin a
    /// deterministic locale (`en_US`) while production follows the
    /// user's system locale.
    var label: String {
        let secondsSince = now.timeIntervalSince(timestamp)
        if secondsSince >= 0 && secondsSince < 3600 {
            let elapsed = Int(secondsSince)
            if elapsed < 60 { return "\(elapsed)s" }
            return "\(elapsed / 60)m"
        }
        if calendar.isDate(timestamp, inSameDayAs: now) {
            return Self.timeFormatter(locale: locale, calendar: calendar)
                .string(from: timestamp)
        }
        let timestampYear = calendar.component(.year, from: timestamp)
        let nowYear = calendar.component(.year, from: now)
        if timestampYear == nowYear {
            return Self.monthDayFormatter(locale: locale, calendar: calendar)
                .string(from: timestamp)
        }
        return Self.fullDateFormatter(locale: locale, calendar: calendar)
            .string(from: timestamp)
    }

    private static func timeFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private static func monthDayFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private static func fullDateFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
        return formatter
    }

    enum AgeBucket {
        case today, yesterday, older
        var displayName: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .older: return "Older"
            }
        }
    }

    /// Calendar-day bucket — used to insert recency section headers in lists.
    var bucket: AgeBucket {
        if calendar.isDate(timestamp, inSameDayAs: now) { return .today }
        if calendar.isDateInYesterday(timestamp) { return .yesterday }
        return .older
    }
}

extension Session {
    var primaryName: String {
        gitRepoName ?? (directory as NSString).lastPathComponent
    }

    var nonStandardDirName: String? {
        guard let repoName = gitRepoName else { return nil }
        let dirName = (directory as NSString).lastPathComponent
        return dirName != repoName ? dirName : nil
    }
}

// MARK: - Sender / preview / status-hint / accessibility helpers
//
// These are the centralized display computations used by the row UI redesign
// (Phase 1 of the Gmail-style row layout). View layers should treat the
// returned values as already-decided structure and concern themselves only
// with rendering — see plan `2026-04-29-1730-row-ui-gmail-redesign.md`.

/// Two-part sender description for the row's line-1 sender slot.
///
/// `repoPart` is always present. `dirSuffix` is non-nil when the directory
/// basename differs from the repo name (worktrees, renamed clones) — in which
/// case the rendering layer paints `repoPart · dirSuffix` and may apply a
/// lower-contrast color to the suffix.
///
/// Note on collisions: when two sessions share the same `(repoPart, dirSuffix)`
/// (e.g. two distinct worktrees both named `tmp`), this helper returns the
/// same value for both. Disambiguating those rows is the line-2 branch slot's
/// job, not this helper's.
struct SenderDisplay: Equatable {
    let repoPart: String
    let dirSuffix: String?
}

/// Priority-chain content for the row's line-1 preview slot. The view layer
/// maps each case to its own typography (regular for `.reply`, italic for
/// `.userPrompt` and `.statusHint`).
enum PreviewContent: Equatable {
    /// Latest assistant message — rendered with no `Claude:`/`Codex:`/`Gemini:`
    /// prefix; that prefix lived only in the previous layout.
    case reply(String)
    /// User's last prompt; rendered as italic `You: <text>` by the view layer.
    case userPrompt(String)
    /// Fallback when neither reply nor prompt is available — derived from
    /// `Session.statusHint(for:)`.
    case statusHint(String)
}

/// Returns the trimmed content of `self` if it has any non-whitespace
/// content; otherwise returns nil. Used to fold "nil", "" and whitespace-only
/// strings into a single notion of "empty" for the preview-priority chain.
extension Optional where Wrapped == String {
    fileprivate var nonEmpty: String? {
        guard let value = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }
}

extension Session {
    /// Two-part sender for the row's line-1 sender slot. See `SenderDisplay`
    /// doc comment for the contract.
    var senderDisplay: SenderDisplay {
        let dirName = (directory as NSString).lastPathComponent
        guard let repoName = gitRepoName else {
            return SenderDisplay(repoPart: dirName, dirSuffix: nil)
        }
        if dirName == repoName {
            return SenderDisplay(repoPart: repoName, dirSuffix: nil)
        }
        return SenderDisplay(repoPart: repoName, dirSuffix: dirName)
    }

    /// Priority-chain preview content for the row's line-1 preview slot.
    ///
    /// Order: `lastReply` (assistant message) → `lastAsk` (user prompt) →
    /// status hint. `nil`, empty strings, and whitespace-only strings are all
    /// treated as "absent" and fall through to the next priority.
    ///
    /// Returns the *first non-empty line* of multi-line text (no character
    /// cap — the view layer truncates).
    var previewContent: PreviewContent {
        if let reply = lastReply.nonEmpty, let line = Self.firstNonEmptyLine(of: reply) {
            return .reply(line)
        }
        if let ask = lastAsk.nonEmpty, let line = Self.firstNonEmptyLine(of: ask) {
            return .userPrompt(line)
        }
        return .statusHint(Self.statusHint(for: status))
    }

    /// Status-hint copy used as the preview-chain fallback. Every
    /// `SessionStatus` case maps to one short string.
    static func statusHint(for status: SessionStatus) -> String {
        switch status {
        case .working:   return "Working\u{2026}"
        case .waiting:   return "Waiting\u{2026}"
        case .idle:      return "Idle"
        case .completed: return "Done"
        case .canceled:  return "Canceled"
        case .stale:     return "Ended"
        }
    }

    /// Composes a unified VoiceOver label for the row's host-icon-with-badge
    /// element.
    ///
    /// Contract:
    /// - Pass `nil` for `hostApp` for **remote** rows (the host part becomes
    ///   `"Globe"` to match the rendered globe SF Symbol).
    /// - Pass a `HostAppInfo` (or `.unknown`) for **local** rows — the
    ///   `name` field is read directly.
    ///
    /// Output shape: `"<host>, <agent>"` — e.g. `"Ghostty, Claude"`,
    /// `"Globe, Codex"`.
    static func accessibilityLabel(hostApp: HostAppInfo?, agent: SessionTool) -> String {
        let hostPart = hostApp?.name ?? "Globe"
        let agentPart: String = {
            switch agent {
            case .claude: return "Claude"
            case .codex:  return "Codex"
            case .gemini: return "Gemini"
            }
        }()
        return "\(hostPart), \(agentPart)"
    }

    /// Returns the first line of `text` that has any non-whitespace content,
    /// trimmed of leading/trailing whitespace. Returns nil when no such line
    /// exists.
    private static func firstNonEmptyLine(of text: String) -> String? {
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
