import Foundation
import SeshctlCore

/// Union of row types the session list view renders. Introduced to merge
/// local `Session` values with cloud `RemoteClaudeCodeSession` values at the
/// view-model output surface without forcing Session to become a union.
///
/// Cloud session IDs (`cse_*`) don't collide with local UUIDs, so a single
/// String id space works without a variant tag.
public enum DisplayRow: Identifiable, Hashable, Sendable {
    case local(Session)
    case remote(RemoteClaudeCodeSession)

    public var id: String {
        switch self {
        case .local(let s):  return s.id
        case .remote(let r): return r.id
        }
    }

    public static func == (lhs: DisplayRow, rhs: DisplayRow) -> Bool {
        // Row identity is driven by session id (UUID or `cse_*`). The
        // underlying Session / RemoteClaudeCodeSession types are `Equatable`
        // but not `Hashable`, so we base equality on the stable id.
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Short name used for tree-view grouping (repo name if any, else
    /// primaryName for local, or a sentinel for remote with no repo).
    public var groupingPrimaryName: String {
        switch self {
        case .local(let s):
            return s.primaryName
        case .remote(let r):
            return Self.repoShortName(from: r.repoUrl) ?? ""
        }
    }

    /// Whether this row contributes to a "repo"-kind tree group (vs a
    /// non-repo group).
    public var isRepo: Bool {
        switch self {
        case .local(let s):  return s.gitRepoName != nil
        case .remote(let r): return r.repoUrl != nil
        }
    }

    /// Timestamp used for Active/Recent sorting.
    public var sortTimestamp: Date {
        switch self {
        case .local(let s):  return s.updatedAt
        case .remote(let r): return r.lastEventAt
        }
    }

    /// Active test. Local rows use `Session.isActive`; cloud rows are active
    /// iff `connection_status == "connected"` (the spike-backed definition
    /// per the plan — running OR idle both count as active while connected).
    public var isActive: Bool {
        switch self {
        case .local(let s):  return s.isActive
        case .remote(let r): return r.connectionStatus == "connected"
        }
    }

    /// Short repo name extracted from a GitHub-style URL like
    /// "https://github.com/julo15/qbk-scheduler" → "qbk-scheduler".
    /// Returns nil when the URL is missing or can't be parsed.
    public static func repoShortName(from url: String?) -> String? {
        guard let url, let parsed = URL(string: url) else { return nil }
        let last = parsed.lastPathComponent
        guard !last.isEmpty, last != "/" else { return nil }
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }
}
