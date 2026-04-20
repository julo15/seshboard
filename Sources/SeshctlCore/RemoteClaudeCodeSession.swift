import Foundation
import GRDB

/// A Claude Code session hosted in claude.ai (Cowork).
///
/// Fetched from the claude.ai internal API and cached in the local SQLite DB
/// for display alongside local sessions. Intentionally does NOT conform to
/// `Codable` — the API response shape is nested (`config.model`,
/// `config.outcomes[].git_info.branches`, etc.) and flattening happens in a
/// separate API-response type. Manual GRDB bridging below stores `branches`
/// as a JSON-encoded TEXT column (SQLite has no array type).
public struct RemoteClaudeCodeSession: FetchableRecord, PersistableRecord, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var model: String
    public var repoUrl: String?
    public var branches: [String]
    public var status: String
    public var workerStatus: String
    public var connectionStatus: String
    public var lastEventAt: Date
    public var createdAt: Date
    public var unread: Bool

    public static let databaseTableName = "remote_claude_code_sessions"

    public var webUrl: URL { URL(string: "https://claude.ai/code/session/\(id)")! }

    public init(
        id: String,
        title: String,
        model: String,
        repoUrl: String?,
        branches: [String],
        status: String,
        workerStatus: String,
        connectionStatus: String,
        lastEventAt: Date,
        createdAt: Date,
        unread: Bool
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.repoUrl = repoUrl
        self.branches = branches
        self.status = status
        self.workerStatus = workerStatus
        self.connectionStatus = connectionStatus
        self.lastEventAt = lastEventAt
        self.createdAt = createdAt
        self.unread = unread
    }

    public init(row: Row) throws {
        id = row["id"]
        title = row["title"]
        model = row["model"]
        repoUrl = row["repo_url"]
        let branchesJson: String = row["branches"] ?? "[]"
        branches = (try? JSONDecoder().decode([String].self, from: Data(branchesJson.utf8))) ?? []
        status = row["status"]
        workerStatus = row["worker_status"]
        connectionStatus = row["connection_status"]
        lastEventAt = row["last_event_at"]
        createdAt = row["created_at"]
        unread = row["unread"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["model"] = model
        container["repo_url"] = repoUrl
        let branchesData = (try? JSONEncoder().encode(branches)) ?? Data("[]".utf8)
        container["branches"] = String(data: branchesData, encoding: .utf8) ?? "[]"
        container["status"] = status
        container["worker_status"] = workerStatus
        container["connection_status"] = connectionStatus
        container["last_event_at"] = lastEventAt
        container["created_at"] = createdAt
        container["unread"] = unread
    }
}
