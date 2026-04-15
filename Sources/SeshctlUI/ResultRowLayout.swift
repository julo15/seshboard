import SwiftUI
import SeshctlCore

struct ResultRowLayout<Status: View, Content: View>: View {
    @ViewBuilder var status: () -> Status
    var ageDisplay: SessionAgeDisplay
    @ViewBuilder var content: () -> Content
    var toolName: String
    var hostApp: HostAppInfo?
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
                .foregroundStyle(ageDisplay.foregroundStyle)
                .frame(width: 40, alignment: .leading)

            // Main content
            content()

            Spacer()

            // Tool label
            Text(toolName)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)

            // Host app icon
            if let hostApp {
                Image(nsImage: hostApp.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }

            // Detail chevron
            if let onDetail {
                Button(action: onDetail) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
