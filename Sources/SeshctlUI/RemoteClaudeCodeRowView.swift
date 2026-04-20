import SwiftUI
import SeshctlCore

/// Row view for a single cloud `RemoteClaudeCodeSession`. Reuses
/// `ResultRowLayout` (the same layout primitive `SessionRowView` +
/// `RecallResultRowView` use) so cloud rows sit natively next to local ones.
///
/// The row is presentation-only — tap / hover / selection highlighting is
/// driven by the parent `SessionListView` / `SessionTreeView`. This view takes
/// `isSelected`, `isUnread`, and `isStale` as inputs and derives its glyph,
/// title styling, and subtitle from them + the session fields.
///
/// Visual grammar (from the plan):
/// - `cloud` glyph for an ordinary cloud row.
/// - `sparkle` accent glyph when the row is unread.
/// - Dimmed + italic title when `isStale` (auth-expired) — the glyph dims to
///   match.
public struct RemoteClaudeCodeRowView: View {
    public let session: RemoteClaudeCodeSession
    public let isSelected: Bool
    public let isUnread: Bool
    public let isStale: Bool

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
            status: { glyphView },
            ageDisplay: SessionAgeDisplay(timestamp: session.lastEventAt),
            content: { mainContent },
            toolName: "claude.ai",
            hostApp: nil,
            onDetail: nil
        )
    }

    // MARK: - Glyph

    @ViewBuilder
    private var glyphView: some View {
        switch Self.glyph(isUnread: isUnread, isStale: isStale) {
        case .cloudIdle:
            Image(systemName: "cloud.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .cloudUnread:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .cloudStale:
            Image(systemName: "cloud")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Main content (title + subtitle)

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleRow
            subtitleRow
        }
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(session.title)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(isStale ? .tertiary : .primary)
                .italic(isStale)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        let text = Self.subtitle(
            repo: DisplayRow.repoShortName(from: session.repoUrl),
            branch: session.branches.first,
            workerStatus: session.workerStatus,
            connectionStatus: session.connectionStatus
        )
        if !text.isEmpty {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Pure helpers (used by views and directly by tests)

    /// Glyph variants the row can render. Pure so unit tests can exercise the
    /// full decision surface without standing up a SwiftUI host.
    public enum Glyph: Equatable, Sendable {
        case cloudIdle
        case cloudUnread
        case cloudStale
    }

    /// Decide which glyph to show. Stale wins over unread — the plan
    /// explicitly says to dim stale rows regardless of unread state.
    /// `nonisolated` so tests can call it without a main-actor hop.
    public nonisolated static func glyph(isUnread: Bool, isStale: Bool) -> Glyph {
        if isStale { return .cloudStale }
        if isUnread { return .cloudUnread }
        return .cloudIdle
    }

    /// Compose the subtitle string: `<repo> · <branch> · <secondary>`.
    /// Empty segments are skipped. `workerStatus` only appears as a tail
    /// segment when it's `"running"` or `"disconnected"`. The base
    /// `"idle" + "connected"` state intentionally hides the worker status
    /// (the cloud glyph already conveys "this session is alive").
    /// `nonisolated` so tests can call it without a main-actor hop.
    public nonisolated static func subtitle(
        repo: String?,
        branch: String?,
        workerStatus: String,
        connectionStatus: String
    ) -> String {
        var parts: [String] = []
        if let repo, !repo.isEmpty { parts.append(repo) }
        if let branch, !branch.isEmpty { parts.append(branch) }
        // Hide workerStatus for the base "idle connected" state.
        if !(workerStatus == "idle" && connectionStatus == "connected") {
            if workerStatus == "running" || workerStatus == "disconnected" {
                parts.append(workerStatus)
            }
        }
        return parts.joined(separator: " · ")
    }
}
