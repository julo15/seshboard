import Foundation
import SeshctlCore

@MainActor
public final class SessionDetailViewModel: ObservableObject {
    public let session: Session?
    public let recallResult: RecallResult?

    @Published public private(set) var turns: [ConversationTurn] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: String?
    @Published public var scrollCommand: ScrollCommand?

    public enum ScrollCommand: Equatable {
        case lineDown
        case lineUp
        case halfPageDown
        case halfPageUp
        case pageDown
        case pageUp
        case top
        case bottom
    }

    /// Display name for the header (repo name or directory basename).
    public var displayName: String {
        if let session {
            return session.gitRepoName ?? (session.directory as NSString).lastPathComponent
        }
        if let recallResult {
            // Last path component of project (e.g., "/Users/julian/Documents/me/seshctl" -> "seshctl")
            return (recallResult.project as NSString).lastPathComponent
        }
        return "Unknown"
    }

    /// Tool name for the header.
    public var toolName: String {
        if let session { return session.tool.rawValue }
        if let recallResult { return recallResult.agent }
        return ""
    }

    /// Git branch for the header (only available from Session).
    public var gitBranch: String? {
        session?.gitBranch
    }

    /// Secondary directory label (when repo name differs from dir name).
    public var directoryLabel: String? {
        guard let session, let repoName = session.gitRepoName else { return nil }
        let dirName = (session.directory as NSString).lastPathComponent
        return dirName != repoName ? dirName : nil
    }

    public init(session: Session) {
        self.session = session
        self.recallResult = nil
    }

    public init(recallResult: RecallResult, session: Session?) {
        self.session = session
        self.recallResult = recallResult
    }

    public func load() {
        let url: URL
        let tool: SessionTool

        if let session {
            guard let sessionURL = TranscriptParser.transcriptURL(for: session) else {
                error = "No transcript available"
                return
            }
            url = sessionURL
            tool = session.tool
        } else if let recallResult {
            url = TranscriptParser.transcriptURL(
                conversationId: recallResult.sessionId,
                directory: recallResult.project
            )
            tool = SessionTool(rawValue: recallResult.agent) ?? .claude
        } else {
            error = "No transcript available"
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "No transcript available"
            return
        }

        isLoading = true
        let fileURL = url
        let parseTool = tool
        Task {
            do {
                let parsed = try await Task.detached {
                    let data = try Data(contentsOf: fileURL)
                    let turns = try TranscriptParser.parse(data: data, tool: parseTool)
                    return turns
                }.value
                self.turns = parsed
                self.isLoading = false
            } catch {
                self.error = "Failed to parse transcript: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}
