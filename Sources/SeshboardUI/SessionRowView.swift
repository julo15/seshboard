import SwiftUI
import SeshboardCore

public struct SessionRowView: View {
    let session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Tool icon
            Text(toolEmoji)
                .font(.title3)

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

                if let ask = session.lastAsk, !ask.isEmpty {
                    Text(ask)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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

    private var toolEmoji: String {
        switch session.tool {
        case .claude: return "C"
        case .gemini: return "G"
        case .codex: return "X"
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
