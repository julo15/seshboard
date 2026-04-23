import SwiftUI
import SeshctlCore

public struct SessionRowView: View {
    let session: Session
    let hostApp: HostAppInfo
    var isUnread: Bool = false
    /// True when this CLI session is also visible as a bridged claude.ai
    /// Code-tab session. When true, line 2 shows a `cloud.fill` glyph next
    /// to the always-present `laptopcomputer` marker — forming the "laptop +
    /// cloud" variant of the three-way row-kind taxonomy (local-only, bridged,
    /// pure-remote). Gated by `ClaudeCodeConnectionStore.hasClaudeConnection`
    /// — when the user has not connected claude.ai, line 2 shows no row-kind
    /// glyph at all.
    var isBridged: Bool = false
    /// True when the claude.ai connection is active (or previously-active).
    /// When false, line 2 suppresses the `laptopcomputer` and `cloud.fill`
    /// row-kind glyphs entirely — users who haven't connected claude.ai see
    /// the pre-cloud layout with no extra chrome.
    var showCloudAffordances: Bool = false

    var onDetail: (() -> Void)?

    @AppStorage("repoAccentBarEnabled") private var repoAccentBarEnabled: Bool = true

    public init(session: Session, hostApp: HostAppInfo, isUnread: Bool = false, isBridged: Bool = false, showCloudAffordances: Bool = false, onDetail: (() -> Void)? = nil) {
        self.session = session
        self.hostApp = hostApp
        self.isUnread = isUnread
        self.isBridged = isBridged
        self.showCloudAffordances = showCloudAffordances
        self.onDetail = onDetail
    }

    public var body: some View {
        ResultRowLayout(
            status: { AnimatedStatusDot(kind: session.status.statusKind) },
            ageDisplay: ageDisplay,
            content: { mainContent },
            toolName: session.tool.rawValue,
            hostApp: hostApp,
            accentColor: repoAccentBarEnabled ? repoAccentColor(for: session.gitRepoName) : nil,
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
                        .foregroundStyle(dirLabelColor(for: session.gitRepoName))
                        .lineLimit(1)
                }
                if let branch = session.gitBranch {
                    Text("·")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(branch)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(branchColor(for: session.gitRepoName))
                        .lineLimit(1)
                }
                if isUnread {
                    UnreadPill()
                }
            }

            // Line 2: row-kind glyphs (see `isBridged` / `showCloudAffordances`
            // docs above for the taxonomy) + message preview or directory path.
            HStack(spacing: 4) {
                if showCloudAffordances {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .help(isBridged
                              ? "Running locally and on claude.ai (Enter focuses the local terminal)"
                              : "Running locally")
                    if isBridged {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .help("Also running on claude.ai")
                    }
                }
                if let (prefix, message) = lastMessagePreview {
                    Text(prefix)
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(directoryPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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

    /// The worktree/dir label next to the repo name. When repo color coding
    /// is on, this inherits the repo's accent color so local worktrees
    /// cluster visually with their repo; when off (or there's no accent
    /// available), falls back to the historic cyan tint.
    private func dirLabelColor(for repoName: String?) -> Color {
        if repoAccentBarEnabled, let color = repoAccentColor(for: repoName) {
            return color
        }
        return .cyan.opacity(0.7)
    }

    /// The git branch next to the repo/dir labels. Inherits the repo's
    /// accent color when coloring is on so same-repo rows cluster; else the
    /// historic `.secondary` treatment.
    private func branchColor(for repoName: String?) -> Color {
        if repoAccentBarEnabled, let color = repoAccentColor(for: repoName) {
            return color
        }
        return .secondary
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
