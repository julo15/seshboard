import SwiftUI
import SeshctlCore

public struct SessionRowView: View {
    let session: Session
    let hostApp: HostAppInfo
    @State private var isPulsing = false
    @State private var isBlinking = false

    var onDetail: (() -> Void)?

    public init(session: Session, hostApp: HostAppInfo, onDetail: (() -> Void)? = nil) {
        self.session = session
        self.hostApp = hostApp
        self.onDetail = onDetail
    }

    private var isWorking: Bool { session.status == .working }
    private var isWaiting: Bool { session.status == .waiting }

    public var body: some View {
        HStack(spacing: 12) {
            // Status dot — overlay approach so animations don't affect layout
            Color.clear
                .frame(width: 22, height: 22)
                .overlay {
                    ZStack {
                        if isWorking {
                            Circle()
                                .fill(statusColor.opacity(0.4))
                                .frame(width: 22, height: 22)
                                .scaleEffect(isPulsing ? 1.2 : 0.6)
                                .opacity(isPulsing ? 0.0 : 1.0)
                            Circle()
                                .fill(statusColor.opacity(0.25))
                                .frame(width: 22, height: 22)
                                .scaleEffect(isPulsing ? 1.8 : 0.6)
                                .opacity(isPulsing ? 0.0 : 0.6)
                        }
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: isWorking ? statusColor.opacity(0.8) : .clear, radius: isPulsing ? 8 : 4)
                            .scaleEffect(isWorking ? (isPulsing ? 1.15 : 0.85) : 1.0)
                            .opacity(isWaiting ? (isBlinking ? 1.0 : 0.3) : 1.0)
                    }
                }
            .onAppear {
                if isWorking {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                if isWaiting {
                    withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: true)) {
                        isBlinking = true
                    }
                }
            }
            .onChange(of: session.status) { newStatus in
                if newStatus == .working {
                    isBlinking = false
                    isPulsing = false
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else if newStatus == .waiting {
                    isPulsing = false
                    isBlinking = false
                    withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: true)) {
                        isBlinking = true
                    }
                } else {
                    isPulsing = false
                    isBlinking = false
                }
            }

            // Relative time
            Text(relativeTime)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            // Main content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(directoryName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(session.tool.rawValue)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(toolColor)
                }

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

            // Detail button — Button stops tap from propagating to parent row handler
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

    private var toolColor: Color {
        switch session.tool {
        case .claude: return .purple
        case .codex: return .green
        case .gemini: return .blue
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .working: return .orange
        case .waiting: return .blue
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
