import SwiftUI
import SeshboardCore

public struct SessionRowView: View {
    let session: Session
    let hostApp: HostAppInfo

    public init(session: Session, hostApp: HostAppInfo) {
        self.session = session
        self.hostApp = hostApp
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Host app icon
            Image(nsImage: hostApp.icon)
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(directoryName)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    Text(relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text(hostApp.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let ask = session.lastAsk, !ask.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(ask)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var statusColor: Color {
        switch session.status {
        case .working: return .orange
        case .idle: return .green
        case .completed: return .gray
        case .canceled: return .red
        case .stale: return .gray.opacity(0.5)
        }
    }

    private var directoryName: String {
        (session.directory as NSString).lastPathComponent
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }
}
