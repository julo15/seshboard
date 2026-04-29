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

    /// Two-column row content: the left column stacks the sender (line 1)
    /// above the branch / row-kind glyphs (line 2) at a fixed width; the
    /// right column hosts the chat preview, vertically centered to span
    /// the full row height in the Gmail "subject + preview reads as
    /// prominent as the sender" idiom.
    ///
    /// **Read-state dimming:** when the row is read (`!isUnread`), dim
    /// the entire content cluster (sender + branch + preview) so the
    /// row recedes visually — mirroring Gmail's read-vs-unread treatment.
    /// Row-chrome (status dot, time, accent bar, icon, pill, chevron)
    /// stays at full opacity so it remains scannable.
    @ViewBuilder
    private var mainContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Sender line (repo · dirSuffix). Italic styling is reserved
                // for R3's `.userPrompt` / `.statusHint` cases on the
                // *preview* side — never duplicated on the sender side.
                // Stale-row dimming happens at the row-opacity tier per R12a.
                SenderText(display: session.senderDisplay)

                // Branch / row-kind line. Per R6, sits at the same metric
                // size as the sender and demotes via lower-contrast color
                // rather than smaller font. Constrained to the column width
                // (via the parent `.frame`), so long branches like
                // `julo/row-ui-gmail-redesign` ellipsize cleanly.
                subtitleRow
            }
            .frame(width: SenderColumnLayout.width, alignment: .leading)

            previewView
        }
        .opacity(isUnread ? 1.0 : 0.6)
    }

    /// Line-2 row-kind-glyphs + branch (or directory-path fallback when
    /// there's no git context).
    @ViewBuilder
    private var subtitleRow: some View {
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
                    .truncationMode(.tail)
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

    /// Maps `Session.previewContent` to the right typography for the chat
    /// preview column. Per the Gmail idiom, the preview is bumped to
    /// `.title3` (15pt) so it sits as the row's most prominent text, and
    /// goes bold on unread / regular on read — pairing with the read-state
    /// opacity dim to make unread rows feel "fresh" against read rows.
    /// `.userPrompt` / `.statusHint` retain italic + dimmer color to
    /// remain visibly distinct from real assistant output (R3).
    @ViewBuilder
    private var previewView: some View {
        switch session.previewContent {
        case .reply(let text):
            Text(text)
                .font(.title3)
                .fontWeight(isUnread ? .bold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .userPrompt(let text):
            Text("You: " + text)
                .font(.title3)
                .fontWeight(isUnread ? .bold : .regular)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .statusHint(let text):
            Text(text)
                .font(.title3)
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
