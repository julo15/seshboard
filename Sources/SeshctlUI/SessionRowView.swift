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

    @AppStorage(AppearanceDefaults.repoAccentBarKey) private var repoAccentBarEnabled: Bool = AppearanceDefaults.repoAccentBarDefault

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
            onDetail: onDetail,
            hostAppBadge: AgentBadgeSpec.forAgent(session.tool),
            iconAccessibilityLabel: Session.accessibilityLabel(hostApp: hostApp, agent: session.tool),
            trailingAccessory: {
                if isUnread {
                    UnreadPill()
                } else {
                    EmptyView()
                }
            }
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: sender (repo · dirSuffix) + preview slot mapped from
            // `Session.previewContent`. Italic styling is reserved here for
            // R3's `.userPrompt` / `.statusHint` cases — never duplicated by
            // the row body. Stale-row dimming happens at the row-opacity
            // tier per R12a, independent of this typography.
            HStack(spacing: 6) {
                SenderText(display: session.senderDisplay)
                    .frame(width: 180, alignment: .leading)
                previewView
            }

            // Line 2: row-kind glyphs (see `isBridged` / `showCloudAffordances`
            // docs above for the taxonomy) + branch (or directory-path
            // fallback when there's no git context). Per R6, line 2 sits at
            // the same metric size as line 1 and demotes via lower-contrast
            // color rather than smaller font.
            HStack(spacing: 4) {
                if showCloudAffordances {
                    Image(systemName: "laptopcomputer")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .help(isBridged
                              ? "Running locally and on claude.ai (Enter focuses the local terminal)"
                              : "Running locally")
                    if isBridged {
                        Image(systemName: "cloud.fill")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .help("Also running on claude.ai")
                    }
                }

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text(branch)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(branchColor())
                        .lineLimit(1)
                } else {
                    // Sessions started outside a git repo fall back to the
                    // directory path with middle truncation, mirroring the
                    // pre-redesign behavior.
                    Text(directoryPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Maps `Session.previewContent` to the right typography for the line-1
    /// preview slot. Per R3, italic styling is reserved for the userPrompt
    /// and statusHint cases — `.reply` is regular weight.
    @ViewBuilder
    private var previewView: some View {
        switch session.previewContent {
        case .reply(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .userPrompt(let text):
            Text("You: " + text)
                .font(.body)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .statusHint(let text):
            Text(text)
                .font(.body)
                .italic()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Branch label color. When per-repo color coding is on, tints with the
    /// repo accent so worktree rows cluster visually with their repo;
    /// otherwise demotes to `.secondary` per R6.
    private func branchColor() -> Color {
        if repoAccentBarEnabled, let color = repoAccentColor(for: session.gitRepoName) {
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
