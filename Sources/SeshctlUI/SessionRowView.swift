import SwiftUI
import SeshctlCore

public struct SessionRowView: View {
    let session: Session
    let hostApp: HostAppInfo
    @State private var isPulsing = false
    @State private var isBlinking = false
    var isUnread: Bool = false

    var onDetail: (() -> Void)?

    public init(session: Session, hostApp: HostAppInfo, isUnread: Bool = false, onDetail: (() -> Void)? = nil) {
        self.session = session
        self.hostApp = hostApp
        self.isUnread = isUnread
        self.onDetail = onDetail
    }

    private var isWorking: Bool { session.status == .working }
    private var isWaiting: Bool { session.status == .waiting }

    public var body: some View {
        ResultRowLayout(
            status: { statusIndicator },
            ageDisplay: ageDisplay,
            content: { mainContent },
            toolName: session.tool.rawValue,
            hostApp: hostApp,
            onDetail: onDetail
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
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
                .shadow(color: isWorking && isPulsing ? statusColor.opacity(0.8) : .clear, radius: isWorking && isPulsing ? 8 : 4)
                .scaleEffect(isWorking ? (isPulsing ? 1.15 : 0.85) : 1.0)
                .opacity(isWaiting ? (isBlinking ? 1.0 : 0.3) : 1.0)
        }
        .drawingGroup()
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
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(session.primaryName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let dirLabel = session.nonStandardDirName {
                    Text("·")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(dirLabel)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
                if let branch = session.gitBranch {
                    Text("·")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(branch)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isUnread {
                    Text("Unread")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            if let (prefix, message) = lastMessagePreview {
                HStack(spacing: 4) {
                    Text(prefix)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(prefix == "You:" ? Color.accentColor : Color.assistantPurple)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(directoryPath)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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

    /// Most recent message preview: (prefix, text). Shows whichever of lastAsk/lastReply
    /// was set most recently. lastReply wins when both exist because the bot always replies
    /// after the user asks.
    private var lastMessagePreview: (String, String)? {
        // If we have a reply, it's the most recent message (bot responds after user asks).
        // If we only have an ask, the user sent it but no reply has been captured yet.
        if let reply = session.lastReply {
            let toolLabel = session.tool.rawValue.capitalized
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? reply
            return ("\(toolLabel):", String(cleaned.prefix(200)))
        }
        if let ask = session.lastAsk {
            let cleaned = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ask
            return ("You:", String(cleaned.prefix(200)))
        }
        return nil
    }

    /// Full directory path with ~ shortening.
    private var directoryPath: String {
        let dir = session.directory
        let home = NSHomeDirectory()
        if dir.hasPrefix(home) {
            return "~" + dir.dropFirst(home.count)
        }
        return dir
    }

    private var ageDisplay: SessionAgeDisplay {
        SessionAgeDisplay(elapsedSeconds: Int(Date().timeIntervalSince(session.updatedAt)))
    }
}
