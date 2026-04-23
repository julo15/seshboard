import SwiftUI
import SeshctlCore

struct ResultRowLayout<Status: View, Content: View>: View {
    @ViewBuilder var status: () -> Status
    var ageDisplay: SessionAgeDisplay
    @ViewBuilder var content: () -> Content
    var toolName: String
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

            // Per-repo accent bar (optional). Stretches to the HStack's
            // vertical height so it matches the title+subtitle content.
            if let accentColor {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor)
                    .frame(width: 3)
            }

            // Main content
            content()

            Spacer()

            // Tool label
            Text(toolName)
                .font(.system(.footnote, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)

            // Host app icon — always takes the same slot so `toolName` lines
            // up horizontally across row types, even for rows without a host
            // app (e.g., remote claude.ai sessions, which fall through to the
            // `hostAppSystemSymbol` placeholder).
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
