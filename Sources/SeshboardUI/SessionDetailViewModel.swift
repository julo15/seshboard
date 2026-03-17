import Foundation
import SeshboardCore

@MainActor
public final class SessionDetailViewModel: ObservableObject {
    public let session: Session

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

    public init(session: Session) {
        self.session = session
    }

    public func load() {
        guard session.tool == .claude else {
            error = "Transcript not available for \(session.tool.rawValue)"
            return
        }

        guard let url = TranscriptParser.transcriptURL(for: session) else {
            error = "No transcript available"
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "No transcript available"
            return
        }

        isLoading = true
        let fileURL = url
        Task {
            do {
                let parsed = try await Task.detached {
                    try TranscriptParser.parse(url: fileURL)
                }.value
                self.turns = parsed
                self.isLoading = false
            } catch {
                self.error = "Failed to parse transcript"
                self.isLoading = false
            }
        }
    }
}
