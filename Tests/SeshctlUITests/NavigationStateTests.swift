import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

@Suite("NavigationState")
@MainActor
struct NavigationStateTests {

    @Test("Starts on list screen")
    func startsOnList() {
        let nav = NavigationState()
        #expect(nav.screen == .list)
        #expect(nav.detailViewModel == nil)
    }

    @Test("openDetail switches to detail screen")
    func openDetail() {
        let nav = NavigationState()
        let session = makeSession()
        nav.openDetail(for: session)
        #expect(nav.screen == .detail)
        #expect(nav.detailViewModel != nil)
        #expect(nav.detailViewModel?.session?.id == session.id)
    }

    @Test("backToList returns to list screen")
    func backToList() {
        let nav = NavigationState()
        nav.openDetail(for: makeSession())
        nav.backToList()
        #expect(nav.screen == .list)
        #expect(nav.detailViewModel == nil)
    }

    @Test("openDetail replaces existing detail")
    func openDetailReplaces() {
        let nav = NavigationState()
        let s1 = makeSession(id: "s1")
        let s2 = makeSession(id: "s2")
        nav.openDetail(for: s1)
        nav.openDetail(for: s2)
        #expect(nav.detailViewModel?.session?.id == "s2")
    }

    // MARK: - Helpers

    private func makeSession(id: String = "test-id") -> Session {
        Session(
            id: id,
            conversationId: nil,
            tool: .claude,
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
