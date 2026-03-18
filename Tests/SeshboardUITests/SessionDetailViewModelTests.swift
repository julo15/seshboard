import Foundation
import Testing

@testable import SeshboardCore
@testable import SeshboardUI

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

    // MARK: - Helpers

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
