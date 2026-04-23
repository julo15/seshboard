import SwiftUI
import SeshctlCore

/// Row view for a single cloud `RemoteClaudeCodeSession`. Reuses
/// `ResultRowLayout` + the shared `AnimatedStatusDot`, `UnreadPill`, and
/// `StatusKind` primitives so local and remote rows sit in the same grid with
/// identical visual grammar.
///
/// - Line 1: `repoShortName · branch · [Unread]` (monospaced; mirrors local
///   `primaryName · gitBranch`).
/// - Line 2: leading `cloud.fill` marker + `title` (regular weight, secondary
///   color — analogous to local's `lastMessagePreview`/directoryPath line).
/// - Status dot: derived via `StatusKind.forRemote(...)`. The shared
///   `AnimatedStatusDot` renders pulse / blink / solid / dim per
///   `StatusKind`'s decisions.
public struct RemoteClaudeCodeRowView: View {
    public let session: RemoteClaudeCodeSession
    public let isSelected: Bool
    public let isUnread: Bool
    public let isStale: Bool

    @AppStorage(AppearanceDefaults.repoAccentBarKey) private var repoAccentBarEnabled: Bool = AppearanceDefaults.repoAccentBarDefault

    public init(
        session: RemoteClaudeCodeSession,
        isSelected: Bool = false,
        isUnread: Bool = false,
        isStale: Bool = false
    ) {
        self.session = session
        self.isSelected = isSelected
        self.isUnread = isUnread
        self.isStale = isStale
    }

    public var body: some View {
        ResultRowLayout(
            status: { AnimatedStatusDot(kind: statusKind) },
            ageDisplay: SessionAgeDisplay(timestamp: session.lastEventAt),
            content: { mainContent },
            toolName: "claude.ai",
            hostApp: nil,
            // Remote sessions live on claude.ai, not in a macOS app — use a
            // neutral globe glyph so we don't imply a specific browser.
            hostAppSystemSymbol: "globe",
            accentColor: (isStale || !repoAccentBarEnabled) ? nil : repoAccentColor(for: repo),
            onDetail: nil
        )
    }

    /// Repo short name extracted from `session.repoUrl`. Used as the
    /// hash key for the accent color and as the displayed repo token.
    /// Returns `""` when no short name can be derived — both downstream
    /// uses fall through to their "no accent" / "hide token" branches.
    private var repo: String {
        DisplayRow.repoShortName(from: session.repoUrl) ?? ""
    }

    private var statusKind: StatusKind {
        StatusKind.forRemote(
            workerStatus: session.workerStatus,
            connectionStatus: session.connectionStatus,
            isStale: isStale
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleRow
            subtitleRow
        }
    }

    @ViewBuilder
    private var titleRow: some View {
        let branch = session.branches.first ?? ""
        HStack(spacing: 6) {
            if !repo.isEmpty {
                Text(repo)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(isStale ? .tertiary : .primary)
                    .italic(isStale)
                    .lineLimit(1)
            }
            if !branch.isEmpty {
                Text("·")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(branch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isStale ? Color.secondary : branchColor(for: repo))
                    .lineLimit(1)
            }
            if isUnread {
                UnreadPill()
            }
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help("Runs on claude.ai only")
            Text(session.title)
                .font(.body)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Branch label color. Remote rows have no dir-label slot so the
    /// branch always picks up the repo accent when coloring is on; when
    /// off, the historic `.secondary` treatment.
    private func branchColor(for repoName: String?) -> Color {
        if repoAccentBarEnabled, let color = repoAccentColor(for: repoName) {
            return color
        }
        return .secondary
    }
}
