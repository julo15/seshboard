import Foundation
import GRDB

public enum SessionStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case idle
    case working
    case waiting
    case completed
    case canceled
    case stale
}

public enum SessionTool: String, Codable, DatabaseValueConvertible, Sendable {
    case claude
    case gemini
    case codex
}

public struct Session: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var id: String
    public var conversationId: String?
    public var tool: SessionTool
    public var directory: String
    public var lastAsk: String?
    public var status: SessionStatus
    public var pid: Int?
    public var hostAppBundleId: String?
    public var hostAppName: String?
    public var windowId: String?
    public var transcriptPath: String?
    public var gitRepoName: String?
    public var gitBranch: String?
    public var startedAt: Date
    public var updatedAt: Date
    public var lastReadAt: Date?

    public static let databaseTableName = "sessions"

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case tool
        case directory
        case lastAsk = "last_ask"
        case status
        case pid
        case hostAppBundleId = "host_app_bundle_id"
        case hostAppName = "host_app_name"
        case windowId = "window_id"
        case transcriptPath = "transcript_path"
        case gitRepoName = "git_repo_name"
        case gitBranch = "git_branch"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case lastReadAt = "last_read_at"
    }

    public var isActive: Bool {
        status == .idle || status == .working || status == .waiting
    }

    public var displayName: String {
        let dirName = (directory as NSString).lastPathComponent

        guard let repoName = gitRepoName else {
            return dirName
        }

        var parts = [repoName]

        if dirName != repoName {
            parts.append(dirName)
        }

        if let branch = gitBranch {
            parts.append(branch)
        }

        return parts.joined(separator: " · ")
    }
}
