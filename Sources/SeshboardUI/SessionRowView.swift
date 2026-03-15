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
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Relative time
            Text(relativeTime)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            // Main content
            VStack(alignment: .leading, spacing: 3) {
                Text(directoryName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let ask = session.lastAsk, !ask.isEmpty {
                    Text(ask)
                        .font(.system(.title3))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Host app icon
            Image(nsImage: hostApp.icon)
                .resizable()
                .frame(width: 24, height: 24)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
        let elapsed = Int(Date().timeIntervalSince(session.updatedAt))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        if elapsed < 86400 { return "\(elapsed / 3600)h" }
        return "\(elapsed / 86400)d"
    }
}
