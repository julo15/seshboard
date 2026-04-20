import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

// MARK: - Glyph tests

@Suite("RemoteClaudeCodeRowView.glyph")
struct RemoteClaudeCodeRowViewGlyphTests {

    @Test("glyph is cloudStale when stale regardless of unread (unread=false)")
    func staleBeatsReadFalse() {
        let glyph = RemoteClaudeCodeRowView.glyph(isUnread: false, isStale: true)
        #expect(glyph == .cloudStale)
    }

    @Test("glyph is cloudStale when stale regardless of unread (unread=true)")
    func staleBeatsReadTrue() {
        let glyph = RemoteClaudeCodeRowView.glyph(isUnread: true, isStale: true)
        #expect(glyph == .cloudStale)
    }

    @Test("glyph is cloudUnread when unread and not stale")
    func unreadGlyph() {
        let glyph = RemoteClaudeCodeRowView.glyph(isUnread: true, isStale: false)
        #expect(glyph == .cloudUnread)
    }

    @Test("glyph is cloudIdle by default (not unread, not stale)")
    func idleGlyph() {
        let glyph = RemoteClaudeCodeRowView.glyph(isUnread: false, isStale: false)
        #expect(glyph == .cloudIdle)
    }
}

// MARK: - Subtitle tests

@Suite("RemoteClaudeCodeRowView.subtitle")
struct RemoteClaudeCodeRowViewSubtitleTests {

    @Test("renders repo · branch when idle connected (no worker suffix)")
    func repoAndBranchIdleConnected() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: "main",
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "qbk-scheduler · main")
    }

    @Test("includes running suffix")
    func includesRunningSuffix() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: "main",
            workerStatus: "running",
            connectionStatus: "connected"
        )
        #expect(subtitle == "qbk-scheduler · main · running")
    }

    @Test("includes disconnected suffix")
    func includesDisconnectedSuffix() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: "main",
            workerStatus: "disconnected",
            connectionStatus: "disconnected"
        )
        #expect(subtitle == "qbk-scheduler · main · disconnected")
    }

    @Test("tolerates missing repo (repo=nil)")
    func tolerantOfMissingRepoNil() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: nil,
            branch: "main",
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "main")
    }

    @Test("tolerates missing branch (branch=nil)")
    func tolerantOfMissingBranchNil() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: nil,
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "qbk-scheduler")
    }

    @Test("empty when no info")
    func emptyWhenNoInfo() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: nil,
            branch: nil,
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "")
    }

    @Test("tolerates empty-string repo (not nil)")
    func tolerantOfEmptyStringRepo() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "",
            branch: "main",
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "main")
    }

    @Test("tolerates empty-string branch (not nil)")
    func tolerantOfEmptyStringBranch() {
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: "",
            workerStatus: "idle",
            connectionStatus: "connected"
        )
        #expect(subtitle == "qbk-scheduler")
    }

    @Test("hides idle worker status even when connection status is disconnected")
    func hidesIdleWorkerEvenDisconnected() {
        // "idle" is neither "running" nor "disconnected" so the suffix branch
        // never adds it — regardless of `connectionStatus`.
        let subtitle = RemoteClaudeCodeRowView.subtitle(
            repo: "qbk-scheduler",
            branch: "main",
            workerStatus: "idle",
            connectionStatus: "disconnected"
        )
        #expect(subtitle == "qbk-scheduler · main")
    }
}
