import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

@Suite("SessionDetailViewModel")
@MainActor
struct SessionDetailViewModelTests {

    @Test("Unsupported tool with no transcript sets error")
    func unsupportedToolError() {
        let session = makeSession(tool: .gemini)
        let vm = SessionDetailViewModel(session: session)
        vm.load()
        #expect(vm.error == "No transcript available")
        #expect(!vm.isLoading)
    }

    @Test("Missing conversationId sets error")
    func missingConversationId() {
        let session = makeSession(conversationId: nil)
        let vm = SessionDetailViewModel(session: session)
        vm.load()
        #expect(vm.error == "No transcript available")
        #expect(!vm.isLoading)
    }

    @Test("Missing transcript file sets error")
    func missingFile() {
        let session = makeSession(conversationId: "nonexistent-\(UUID().uuidString)")
        let vm = SessionDetailViewModel(session: session)
        vm.load()
        #expect(vm.error == "No transcript available")
        #expect(!vm.isLoading)
    }

    @Test("Scroll command can be set and cleared")
    func scrollCommand() {
        let vm = SessionDetailViewModel(session: makeSession())
        #expect(vm.scrollCommand == nil)
        vm.scrollCommand = .bottom
        #expect(vm.scrollCommand == .bottom)
        vm.scrollCommand = nil
        #expect(vm.scrollCommand == nil)
    }

    @Test("All scroll command cases are distinct")
    func scrollCommandCases() {
        let all: [SessionDetailViewModel.ScrollCommand] = [
            .lineDown, .lineUp, .halfPageDown, .halfPageUp,
            .pageDown, .pageUp, .top, .bottom
        ]
        // Verify each is unique
        for i in 0..<all.count {
            for j in 0..<all.count {
                if i == j {
                    #expect(all[i] == all[j])
                } else {
                    #expect(all[i] != all[j])
                }
            }
        }
    }

    @Test("RecallResult init with no session sets displayName from project")
    func recallResultNoSession() {
        let result = makeRecallResult(project: "/Users/julian/Documents/me/seshctl")
        let vm = SessionDetailViewModel(recallResult: result, session: nil)
        #expect(vm.displayName == "seshctl")
        #expect(vm.toolName == "claude")
        #expect(vm.gitBranch == nil)
        #expect(vm.directoryLabel == nil)
        #expect(vm.session == nil)
        #expect(vm.recallResult != nil)
    }

    @Test("RecallResult init with matching session uses session data")
    func recallResultWithSession() {
        let result = makeRecallResult()
        let session = makeSession(tool: .claude, conversationId: "conv-123")
        let vm = SessionDetailViewModel(recallResult: result, session: session)
        #expect(vm.session != nil)
        #expect(vm.displayName == (session.gitRepoName ?? "tmp"))
        #expect(vm.toolName == "claude")
    }

    @Test("RecallResult with missing transcript file shows error")
    func recallResultMissingTranscript() {
        let result = makeRecallResult(sessionId: "nonexistent-\(UUID().uuidString)")
        let vm = SessionDetailViewModel(recallResult: result, session: nil)
        vm.load()
        #expect(vm.error == "No transcript available")
        #expect(!vm.isLoading)
    }

    // MARK: - Helpers

    private func makeRecallResult(
        sessionId: String = "conv-123",
        project: String = "/tmp",
        agent: String = "claude"
    ) -> RecallResult {
        RecallResult(
            agent: agent,
            role: "user",
            sessionId: sessionId,
            project: project,
            timestamp: Date().timeIntervalSince1970,
            score: 0.95,
            resumeCmd: "claude --resume conv-123",
            text: "test recall text"
        )
    }

    private func makeSession(
        tool: SessionTool = .claude,
        conversationId: String? = "test-conv-id"
    ) -> Session {
        Session(
            id: UUID().uuidString,
            conversationId: conversationId,
            tool: tool,
            directory: "/tmp",
            lastAsk: nil,
            lastReply: nil,
            status: .idle,
            pid: 1234,
            hostAppBundleId: nil,
            hostAppName: nil,
            windowId: nil,
            transcriptPath: nil,
            startedAt: Date(),
            updatedAt: Date()
        )
    }
}
