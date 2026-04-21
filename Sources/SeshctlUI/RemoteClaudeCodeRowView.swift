import SwiftUI
import SeshctlCore

/// Row view for a single cloud `RemoteClaudeCodeSession`. Reuses
/// `ResultRowLayout` (the same layout primitive `SessionRowView` +
/// `RecallResultRowView` use) so cloud rows sit natively next to local ones.
///
/// Visual grammar (mirrors `SessionRowView` so local/remote rows share a grid):
/// - Line 1: `repoShortName · branch · [Unread]` (monospaced; same shape as
///   local's `primaryName · gitBranch`).
/// - Line 2: leading `cloud.fill` marker + `title` (regular weight, secondary
///   color — analogous to local's `lastMessagePreview`/directoryPath line).
/// - Status dot on the left: `.running` pulsing orange / `.waiting` blinking
///   blue (pending user action) / `.idle` green / `.offline` gray / `.stale`
///   dim gray. The `.waiting` state matches the local `SessionStatus.waiting`
///   treatment.
public struct RemoteClaudeCodeRowView: View {
    public let session: RemoteClaudeCodeSession
    public let isSelected: Bool
    public let isUnread: Bool
    public let isStale: Bool
    @State private var isPulsing = false
    @State private var isBlinking = false

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
            status: { statusIndicator },
            ageDisplay: SessionAgeDisplay(timestamp: session.lastEventAt),
            content: { mainContent },
            toolName: "claude.ai",
            hostApp: nil,
            // Remote sessions live on claude.ai, not in a macOS app — use a
            // generic browser glyph in the host-app slot so the row still
            // has something visually balanced with local rows that show an
            // actual terminal/IDE app icon.
            hostAppSystemSymbol: "safari",
            onDetail: nil
        )
    }

    // MARK: - Status indicator (colored dot, pulsing when running, blinking when waiting)

    private var currentStatus: Status {
        Self.status(
            workerStatus: session.workerStatus,
            connectionStatus: session.connectionStatus,
            isStale: isStale
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        let color = Self.color(for: currentStatus)
        ZStack {
            if currentStatus == .running {
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .scaleEffect(isPulsing ? 1.2 : 0.6)
                    .opacity(isPulsing ? 0.0 : 1.0)
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 22, height: 22)
                    .scaleEffect(isPulsing ? 1.8 : 0.6)
                    .opacity(isPulsing ? 0.0 : 0.6)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(
                    color: currentStatus == .running && isPulsing ? color.opacity(0.8) : .clear,
                    radius: currentStatus == .running && isPulsing ? 8 : 4
                )
                .scaleEffect(currentStatus == .running ? (isPulsing ? 1.15 : 0.85) : 1.0)
                .opacity(currentStatus == .waiting ? (isBlinking ? 1.0 : 0.3) : 1.0)
        }
        .drawingGroup()
        .onAppear { startAnimationsIfNeeded() }
        .onChange(of: session.workerStatus) { _ in
            isPulsing = false
            isBlinking = false
            startAnimationsIfNeeded()
        }
    }

    private func startAnimationsIfNeeded() {
        switch currentStatus {
        case .running:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        case .waiting:
            withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        case .idle, .offline, .stale:
            break
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
        let repo = DisplayRow.repoShortName(from: session.repoUrl) ?? ""
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isUnread {
                Text("Unread")
                    .font(.system(.footnote, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(session.title)
                .font(.body)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Pure helpers (used by views and directly by tests)

    /// Status the row reflects. Matches the local-session color vocabulary so
    /// cloud rows sit visually alongside local rows.
    public enum Status: Equatable, Sendable {
        /// Worker is running — pulsing orange, like a local `.working` row.
        case running
        /// Worker is waiting on user input (pending action) — blinking blue,
        /// like a local `.waiting` row. Trigger is heuristic for now until we
        /// observe the actual API value; see `status(workerStatus:...)`.
        case waiting
        /// Worker is idle and the session is connected — solid green, alive.
        case idle
        /// Session is disconnected — solid gray, like a local `.completed` row.
        case offline
        /// Auth expired; cached row being shown — dim gray.
        case stale
    }

    /// Decide the row's status. Stale beats everything (the cache is no longer
    /// authoritative). `nonisolated` so tests can call without a main-actor hop.
    ///
    /// The `.waiting` trigger is best-effort: we haven't observed a live API
    /// response for a Code session that's paused on a permission prompt, so
    /// we match on plausible values (`"waiting"`, `"requires_action"`) and let
    /// the fetcher log any other unknown `worker_status` for future tuning.
    public nonisolated static func status(
        workerStatus: String,
        connectionStatus: String,
        isStale: Bool
    ) -> Status {
        if isStale { return .stale }
        if workerStatus == "running" { return .running }
        if workerStatus == "waiting" || workerStatus == "requires_action" {
            return .waiting
        }
        if connectionStatus == "disconnected" || workerStatus == "disconnected" {
            return .offline
        }
        return .idle
    }

    /// Map a status to the dot color. `nonisolated` to keep the pure-helper
    /// discipline consistent with the other helpers on this type.
    public nonisolated static func color(for status: Status) -> Color {
        switch status {
        case .running: return .orange
        case .waiting: return .blue
        case .idle: return .green
        case .offline: return .gray
        case .stale: return .gray.opacity(0.5)
        }
    }
}
