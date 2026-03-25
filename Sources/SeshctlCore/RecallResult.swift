import Foundation

public struct RecallResult: Codable, Sendable {
    public let agent: String
    public let role: String
    public let sessionId: String
    public let project: String
    public let timestamp: Double
    public let score: Double
    public let resumeCmd: String
    public let text: String

    enum CodingKeys: String, CodingKey {
        case agent
        case role
        case sessionId = "session_id"
        case project
        case timestamp
        case score
        case resumeCmd = "resume_cmd"
        case text
    }

    public init(
        agent: String,
        role: String,
        sessionId: String,
        project: String,
        timestamp: Double,
        score: Double,
        resumeCmd: String,
        text: String
    ) {
        self.agent = agent
        self.role = role
        self.sessionId = sessionId
        self.project = project
        self.timestamp = timestamp
        self.score = score
        self.resumeCmd = resumeCmd
        self.text = text
    }
}
