import SwiftUI
import SeshctlCore

/// Row view for a single cloud `RemoteClaudeCodeSession`. Mirrors the local
/// `SessionRowView` shape from Unit 5 of the Gmail-style row layout — same
/// `ResultRowLayout` slots, same line-1 `SenderText` + preview pattern, same
/// trailing-accessory slot — and swaps in remote-specific data sources so
/// local and remote rows sit in the same grid with identical visual grammar.
///
/// - Line 1: `SenderText(senderDisplay)` + preview slot. `senderDisplay` is
///   sourced from `repoUrl` (`Remote` fallback) via the helper in
///   `RemoteClaudeCodeSession+Display.swift`. The preview is always
///   `.reply(title)` — remote sessions have no `lastReply` / `lastAsk`
///   conversation chain, so R3's italic priority chain doesn't apply.
/// - Line 2: `cloud.fill` glyph + `branches[0]`. When `branches` is empty,
///   `branchDisplay` is nil and the entire line collapses to `EmptyView()`
///   (per R11) so the row reads as single-line. Gated on
///   `showCloudAffordances` so users without a claude.ai connection don't
///   see cloud chrome — though in practice remote rows only render when the
///   user has connected, so this defaults to `true`.
/// - Right side: `globe` SF Symbol + Claude corner badge via
///   `BadgedIcon`, with the unified `Globe, Claude` accessibility label
///   from `Session.accessibilityLabel(hostApp:agent:)`. Phase 1 keeps the
///   `claude.ai` text label as a recognition safety net alongside the
///   badge — Phase 2 removes the label.
/// - Status dot: derived via `StatusKind.forRemote(...)`. The shared
///   `AnimatedStatusDot` renders pulse / blink / solid / dim per
///   `StatusKind`'s decisions.
/// - Stale rows dim at the row-opacity tier (per R12a): the body picks up
///   `.opacity(0.6)` when `isStale` so the dimming reads as inactive-row
///   chrome rather than line-1 typography. Italic on line 1 is reserved for
///   R3's `.userPrompt` / `.statusHint` cases — neither of which applies
///   to remote rows.
public struct RemoteClaudeCodeRowView: View {
    public let session: RemoteClaudeCodeSession
    public let isSelected: Bool
    public let isUnread: Bool
    public let isStale: Bool
    /// Whether to render the line-2 `cloud.fill` glyph. Mirrors the gating
    /// used by `SessionRowView` for the laptop/cloud trio: when the user
    /// hasn't connected claude.ai there's no cloud chrome anywhere. Remote
    /// rows only surface when a connection exists, so this defaults to
    /// `true` — but the parameter exists so callers can suppress the glyph
    /// in preview / test contexts and so the gating contract is explicit.
    public let showCloudAffordances: Bool

    @AppStorage(AppearanceDefaults.repoAccentBarKey) private var repoAccentBarEnabled: Bool = AppearanceDefaults.repoAccentBarDefault

    public init(
        session: RemoteClaudeCodeSession,
        isSelected: Bool = false,
        isUnread: Bool = false,
        isStale: Bool = false,
        showCloudAffordances: Bool = true
    ) {
        self.session = session
        self.isSelected = isSelected
        self.isUnread = isUnread
        self.isStale = isStale
        self.showCloudAffordances = showCloudAffordances
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
            onDetail: nil,
            hostAppBadge: AgentBadgeSpec.forRemote(model: session.model),
            iconAccessibilityLabel: Session.accessibilityLabel(hostApp: nil, agent: .claude),
            trailingAccessory: {
                if isUnread {
                    UnreadPill()
                } else {
                    EmptyView()
                }
            }
        )
        // Stale-row dimming lives at the row-opacity tier (R12a). Line-1
        // italic is reserved for R3's userPrompt/statusHint cases — which
        // remote rows never hit — so the body styling stays regular and
        // staleness reads through opacity instead.
        .opacity(isStale ? 0.6 : 1.0)
    }

    /// Repo short name extracted from `session.repoUrl`. Used as the
    /// hash key for the accent color. Returns `""` when no short name can
    /// be derived — the accent-color path falls through to its "no accent"
    /// branch.
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
            // Line 1: sender (repo extracted from repoUrl, or "Remote") +
            // preview slot. Remote rows always hit `.reply(title)` so the
            // preview renders as regular weight `.secondary` per R6.
            HStack(spacing: 6) {
                SenderText(display: session.senderDisplay)
                    .frame(width: SenderColumnLayout.width, alignment: .leading)
                previewView
            }

            // Line 2: cloud.fill glyph + branch. Collapses entirely when
            // `branches` is empty per R11 — `branchDisplay` returns nil and
            // the closure yields an empty view, so the row reads as
            // single-line.
            subtitleRow
        }
    }

    /// Line-1 preview slot. Remote sessions always pass through the
    /// `.reply` case (title-as-preview) — `previewContent` on
    /// `RemoteClaudeCodeSession` is hardcoded to `.reply(title)` because
    /// there's no `lastReply` / `lastAsk` priority chain. The other cases
    /// are handled here for exhaustiveness in case the helper's contract
    /// ever loosens to allow status-hint fallbacks (e.g., for a "sync
    /// pending" surface), keeping the typography mapping consistent with
    /// `SessionRowView.previewView`.
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

    /// Line 2: `cloud.fill` prefix glyph + branch. The glyph used to
    /// decorate the title; it now lives only on line 2 per R5a, mirroring
    /// `SessionRowView`'s laptop/cloud trio (this row's "cloud only"
    /// variant since remote sessions are pure-cloud by definition).
    /// Returns `EmptyView()` when `branchDisplay` is nil so the entire
    /// line collapses (R11).
    @ViewBuilder
    private var subtitleRow: some View {
        if let branch = session.branchDisplay, !branch.isEmpty {
            HStack(spacing: 4) {
                if showCloudAffordances {
                    Image(systemName: "cloud.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .help("Runs on claude.ai only")
                }
                Text(branch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(branchColor(for: repo))
                    .lineLimit(1)
            }
        } else {
            EmptyView()
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
