import SwiftUI
import SeshctlCore

public struct SessionRowView: View {
    let session: Session
    let hostApp: HostAppInfo
    var isUnread: Bool = false
    /// True when this CLI session is also visible as a bridged claude.ai
    /// Code-tab session. Renders a small cloud marker after the branch so
    /// the user knows Enter focuses the terminal but the same conversation
    /// lives on claude.ai too.
    var isBridged: Bool = false

    var onDetail: (() -> Void)?

    public init(session: Session, hostApp: HostAppInfo, isUnread: Bool = false, isBridged: Bool = false, onDetail: (() -> Void)? = nil) {
        self.session = session
        self.hostApp = hostApp
        self.isUnread = isUnread
        self.isBridged = isBridged
        self.onDetail = onDetail
    }

    public var body: some View {
        ResultRowLayout(
            status: { AnimatedStatusDot(kind: session.status.statusKind) },
            ageDisplay: ageDisplay,
            content: { mainContent },
            toolName: session.tool.rawValue,
            hostApp: hostApp,
            onDetail: onDetail
        )
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
                    UnreadPill()
                }
                if isBridged {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .help("Also bridged to claude.ai")
                }
            }

            if let (prefix, message) = lastMessagePreview {
                HStack(spacing: 4) {
                    Text(prefix)
                        .font(.body.weight(.medium))
                        .foregroundStyle(prefix == "You:" ? Color.accentColor : Color.assistantPurple)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text(directoryPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        SessionAgeDisplay(timestamp: session.updatedAt)
    }
}
