import SwiftUI
import SeshctlCore

struct ResultRowLayout<Status: View, Content: View, Trailing: View>: View {
    @ViewBuilder var status: () -> Status
    var ageDisplay: SessionAgeDisplay
    @ViewBuilder var content: () -> Content
    var hostApp: HostAppInfo?
    /// Fallback SF Symbol name used in the host-app slot when `hostApp` is
    /// nil. Lets non-local rows (e.g., remote claude.ai sessions that have no
    /// associated macOS app) still render something recognizable in that
    /// column instead of empty space. Rendered as a secondary-colored template
    /// glyph so it reads as a placeholder, not a real app icon.
    var hostAppSystemSymbol: String? = nil
    /// Per-row accent color. When non-nil, renders a thin vertical bar just
    /// left of the main content — used for per-repo color coding so sessions
    /// from the same repo cluster visually in the flat list.
    var accentColor: Color? = nil
    var onDetail: (() -> Void)?
    /// Optional agent-kind corner badge composed over the host-app icon.
    /// When non-nil, the icon site renders a `BadgedIcon` instead of the
    /// bare `Image`, with the unified accessibility label from
    /// `iconAccessibilityLabel`. When nil, falls back to the historic
    /// bare-icon rendering — used by callers that don't carry agent
    /// identity (e.g. `RecallResultRowView`).
    var hostAppBadge: AgentBadgeSpec? = nil
    /// Unified VoiceOver label for the composite host-icon-with-badge
    /// element. Required when `hostAppBadge` is set; ignored otherwise.
    /// Build via `Session.accessibilityLabel(hostApp:agent:)`.
    var iconAccessibilityLabel: String? = nil
    /// Optional trailing-accessory slot rendered between the host-app icon
    /// and the chevron. Defaults to `EmptyView` via the constrained
    /// extension below, so existing callers compile unchanged. Used for
    /// row-chrome accessories like `UnreadPill` that anchor the row's
    /// right edge as a focused-attention signal.
    ///
    /// Sized via SwiftUI's natural layout: an `EmptyView` collapses to
    /// zero width (no phantom right-edge gap), while real content takes
    /// its intrinsic width. Do **not** wrap this in an unconditional
    /// `.frame(minWidth: ...)` — that recreates the 20pt phantom-gap
    /// regression flagged in
    /// `.agents/reviews/2026-04-21-1500-remote-rows-first-class-r1.md`.
    @ViewBuilder var trailingAccessory: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Color.clear
                .frame(width: 22, height: 22)
                .overlay { status() }

            // Relative time
            Text(ageDisplay.label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            // Per-repo accent bar slot (always 2pt wide so non-accented rows
            // line up with accented ones — when `accentColor` is nil the
            // slot renders `Color.clear`, preserving the column grid).
            // Stretches to the HStack's vertical height so it matches the
            // title+subtitle content.
            RoundedRectangle(cornerRadius: 1)
                .fill(accentColor ?? .clear)
                .frame(width: 2)

            // Main content
            content()

            Spacer()

            // Trailing-accessory slot (e.g., UnreadPill). Sits to the *left*
            // of the host-app icon so the unread signal anchors the right
            // edge of the content area, with the icon and chevron forming the
            // row's persistent right-side chrome. EmptyView default collapses
            // to zero width so non-pill rows don't grow a phantom gap.
            trailingAccessory()

            // Host app icon — always takes the same slot, even for rows
            // without a host app (e.g., remote claude.ai sessions, which fall
            // through to the `hostAppSystemSymbol` placeholder). When
            // `hostAppBadge` is set, the icon is composited with an agent-kind
            // corner badge via `BadgedIcon`; otherwise renders the bare image
            // as before.
            Group {
                if let hostAppBadge {
                    let baseImage: Image? = {
                        if let hostApp {
                            return Image(nsImage: hostApp.icon)
                        } else if let hostAppSystemSymbol {
                            return Image(systemName: hostAppSystemSymbol)
                        } else {
                            return nil
                        }
                    }()
                    if let baseImage {
                        BadgedIcon(
                            base: baseImage,
                            badge: hostAppBadge,
                            accessibilityLabel: iconAccessibilityLabel ?? ""
                        )
                    } else {
                        Color.clear
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                } else {
                    Group {
                        if let hostApp {
                            Image(nsImage: hostApp.icon)
                                .resizable()
                        } else if let hostAppSystemSymbol {
                            Image(systemName: hostAppSystemSymbol)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            Color.clear
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
            }

            // Detail chevron — same fixed-width slot whether or not the row
            // offers a detail action.
            Group {
                if let onDetail {
                    Button(action: onDetail) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

// MARK: - No-trailing-accessory init for existing callers
//
// Swift cannot express a default value directly for a generic-parameter
// closure (`trailingAccessory: () -> Trailing` defaulting to
// `{ EmptyView() }`). Instead, this constrained extension provides an init
// that omits the parameter entirely and forwards to the primary memberwise
// init with `{ EmptyView() }`. All three current call sites
// (`SessionRowView`, `RecallResultRowView`, `RemoteClaudeCodeRowView`)
// compile unchanged through this overload.
extension ResultRowLayout where Trailing == EmptyView {
    init(
        @ViewBuilder status: @escaping () -> Status,
        ageDisplay: SessionAgeDisplay,
        @ViewBuilder content: @escaping () -> Content,
        hostApp: HostAppInfo?,
        hostAppSystemSymbol: String? = nil,
        accentColor: Color? = nil,
        onDetail: (() -> Void)? = nil,
        hostAppBadge: AgentBadgeSpec? = nil,
        iconAccessibilityLabel: String? = nil
    ) {
        self.init(
            status: status,
            ageDisplay: ageDisplay,
            content: content,
            hostApp: hostApp,
            hostAppSystemSymbol: hostAppSystemSymbol,
            accentColor: accentColor,
            onDetail: onDetail,
            hostAppBadge: hostAppBadge,
            iconAccessibilityLabel: iconAccessibilityLabel,
            trailingAccessory: { EmptyView() }
        )
    }
}
