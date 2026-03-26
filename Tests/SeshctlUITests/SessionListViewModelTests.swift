import Foundation
import Testing

import GRDB

@testable import SeshctlCore
@testable import SeshctlUI


@Suite("SessionListViewModel")
struct SessionListViewModelTests {
    @Test("Refresh loads sessions from database")
    @MainActor
    func refreshLoadsSessions() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/project-a", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp/project-b", pid: 2222)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.sessions.count == 2)
        #expect(vm.error == nil)
    }

    @Test("Active sessions filters correctly")
    @MainActor
    func activeSessions() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        try db.endSession(pid: 2222, tool: .gemini)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.activeSessions.count == 1)
        #expect(vm.activeSessions[0].tool == .claude)
    }

    @Test("Recent sessions filters correctly")
    @MainActor
    func recentSessions() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        try db.endSession(pid: 2222, tool: .gemini)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.recentSessions.count == 1)
        #expect(vm.recentSessions[0].tool == .gemini)
    }

    @Test("Empty database shows no sessions")
    @MainActor
    func emptySessions() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.sessions.isEmpty)
        #expect(vm.activeSessions.isEmpty)
        #expect(vm.recentSessions.isEmpty)
        #expect(vm.error == nil)
    }

    @Test("Refresh updates after database changes")
    @MainActor
    func refreshUpdates() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)

        vm.refresh()
        #expect(vm.sessions.isEmpty)

        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        vm.refresh()
        #expect(vm.sessions.count == 1)

        try db.updateSession(pid: 1234, tool: .claude, ask: "hello", status: .working)
        vm.refresh()
        #expect(vm.sessions[0].status == .working)
        #expect(vm.sessions[0].lastAsk == "hello")
    }

    @Test("Working sessions appear in active list")
    @MainActor
    func workingIsActive() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.activeSessions.count == 1)
        #expect(vm.activeSessions[0].status == .working)
    }

    @Test("Stale sessions appear in recent list")
    @MainActor
    func staleIsRecent() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 99999)
        _ = try db.gc(isProcessAlive: { _ in false })

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.activeSessions.isEmpty)
        #expect(vm.recentSessions.count == 1)
        #expect(vm.recentSessions[0].status == .stale)
    }

    // MARK: - Selection Tests

    @Test("Selection starts at 0")
    @MainActor
    func selectionStartsAtZero() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        #expect(vm.selectedIndex == 0)
    }

    @Test("Move selection down")
    @MainActor
    func moveDown() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...3 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.moveSelectionDown()
        #expect(vm.selectedIndex == 1)
        vm.moveSelectionDown()
        #expect(vm.selectedIndex == 2)
    }

    @Test("Move selection down clamps at end")
    @MainActor
    func moveDownClamps() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.moveSelectionDown()
        vm.moveSelectionDown()
        vm.moveSelectionDown()
        #expect(vm.selectedIndex == 0) // only 1 session
    }

    @Test("Move selection up")
    @MainActor
    func moveUp() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...3 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.selectedIndex = 2
        vm.moveSelectionUp()
        #expect(vm.selectedIndex == 1)
        vm.moveSelectionUp()
        #expect(vm.selectedIndex == 0)
    }

    @Test("Move selection up clamps at top")
    @MainActor
    func moveUpClamps() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.moveSelectionUp()
        #expect(vm.selectedIndex == 0)
    }

    @Test("Selected session returns correct session")
    @MainActor
    func selectedSession() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        // sessions are ordered by updated_at DESC, so gemini (pid 2) is first
        #expect(vm.selectedSession?.tool == .gemini)

        vm.moveSelectionDown()
        #expect(vm.selectedSession?.tool == .claude)
    }

    @Test("Selected session returns nil for empty list")
    @MainActor
    func selectedSessionEmpty() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.selectedSession == nil)
    }

    @Test("Reset selection goes back to 0")
    @MainActor
    func resetSelection() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...3 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.selectedIndex = 2
        vm.resetSelection()
        #expect(vm.selectedIndex == 0)
    }

    // MARK: - Focus Memory Tests

    @Test("Reset selection restores remembered session")
    @MainActor
    func resetSelectionRestoresRemembered() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...3 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        let vm = SessionListViewModel(database: db, enableGC: false, focusMemoryWindow: 60)
        vm.refresh()

        // Remember the second session (index 1)
        let target = vm.orderedSessions[1]
        vm.rememberFocusedSession(target)

        vm.selectedIndex = 0
        vm.resetSelection()
        #expect(vm.selectedIndex == 1)
    }

    @Test("Reset selection falls back to 0 after memory window expires")
    @MainActor
    func resetSelectionExpired() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...3 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        // Use a tiny window so it expires immediately
        let vm = SessionListViewModel(database: db, enableGC: false, focusMemoryWindow: 0)
        vm.refresh()

        let target = vm.orderedSessions[1]
        vm.rememberFocusedSession(target)

        vm.selectedIndex = 2
        vm.resetSelection()
        #expect(vm.selectedIndex == 0)
    }

    @Test("Reset selection falls back to 0 when remembered session is gone")
    @MainActor
    func resetSelectionMissingSession() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2)

        let vm = SessionListViewModel(database: db, enableGC: false, focusMemoryWindow: 60)
        vm.refresh()

        // Remember gemini session, then end it
        let gemini = vm.orderedSessions.first { $0.tool == .gemini }!
        vm.rememberFocusedSession(gemini)

        try db.endSession(pid: 2, tool: .gemini)
        vm.refresh()

        // Completed session should not be restored — falls back to 0
        vm.resetSelection()
        #expect(vm.selectedIndex == 0)
    }

    @Test("Focus memory distinguishes sessions in the same directory")
    @MainActor
    func focusMemoryByIdNotDirectory() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/shared", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/shared", pid: 2)

        let vm = SessionListViewModel(database: db, enableGC: false, focusMemoryWindow: 60)
        vm.refresh()

        let ordered = vm.orderedSessions
        // Remember the second session specifically
        let second = ordered[1]
        vm.rememberFocusedSession(second)

        vm.selectedIndex = 0
        vm.resetSelection()
        #expect(vm.selectedIndex == 1)
        #expect(vm.selectedSession?.id == second.id)
    }

    // MARK: - Kill Flow Tests

    @Test("requestKill sets pendingKillSessionId for active session")
    @MainActor
    func requestKillSetsIdForActive() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp/kill", pid: 5555)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestKill()
        #expect(vm.pendingKillSessionId == session.id)
    }

    @Test("requestKill does nothing for inactive session")
    @MainActor
    func requestKillInactiveNoop() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/kill", pid: 5555)
        try db.endSession(pid: 5555, tool: .claude)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestKill()
        #expect(vm.pendingKillSessionId == nil)
    }

    @Test("requestKill does nothing for session without PID")
    @MainActor
    func requestKillNoPidNoop() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp/kill", pid: 5555)

        // Clear the PID directly via GRDB to simulate a session with no PID
        try db.dbPool.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE sessions SET pid = NULL WHERE id = ?",
                arguments: [session.id]
            )
        }

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestKill()
        #expect(vm.pendingKillSessionId == nil)
    }

    @Test("cancelKill clears pendingKillSessionId")
    @MainActor
    func cancelKillClearsId() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/kill", pid: 5555)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestKill()
        #expect(vm.pendingKillSessionId != nil)

        vm.cancelKill()
        #expect(vm.pendingKillSessionId == nil)
    }

    @Test("Selection change clears pendingKillSessionId")
    @MainActor
    func selectionChangeClearsKillId() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestKill()
        #expect(vm.pendingKillSessionId != nil)

        vm.moveSelectionDown()
        #expect(vm.pendingKillSessionId == nil)
    }

    // MARK: - Unread Tests

    @Test("Session with activity after start is unread")
    @MainActor
    func activityAfterStartIsUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        // Simulate activity after start so updatedAt > lastReadAt
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1234, tool: .claude, ask: "hello", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.unreadSessionIds.contains(session.id))
    }

    @Test("Never-read session in working state is NOT unread")
    @MainActor
    func neverReadWorkingNotUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(!vm.unreadSessionIds.contains(session.id))
    }

    @Test("Working sessions excluded from unread set, waiting sessions included")
    @MainActor
    func workingNotUnreadWaitingIsUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let s1 = try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1111, tool: .claude, status: .working)

        let s2 = try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 2222, tool: .gemini, status: .working)
        try db.updateSession(pid: 2222, tool: .gemini, status: .waiting)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        // Working is not unread (still in progress)
        #expect(!vm.unreadSessionIds.contains(s1.id))
        // Waiting IS unread (needs user attention)
        #expect(vm.unreadSessionIds.contains(s2.id))
    }

    @Test("Unread set includes sessions with updatedAt > lastReadAt in actionable states")
    @MainActor
    func unreadAfterUpdate() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // Mark as read
        try db.markSessionRead(id: session.id)

        // Ensure updatedAt > lastReadAt (avoid same-millisecond timestamps)
        Thread.sleep(forTimeInterval: 0.01)

        // Update the session (simulates new activity)
        try db.updateSession(pid: 1234, tool: .claude, ask: "new question", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.unreadSessionIds.contains(session.id))
    }

    @Test("markSessionRead removes session from unread set")
    @MainActor
    func markReadRemovesFromUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        // Simulate activity so session becomes unread
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1234, tool: .claude, ask: "hello", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.unreadSessionIds.contains(session.id))

        let updated = try db.findActiveSession(pid: 1234, tool: .claude)!
        vm.markSessionRead(updated)
        #expect(!vm.unreadSessionIds.contains(session.id))
    }

    @Test("Completed session is unread when completed after start")
    @MainActor
    func completedAfterStartIsUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        // Ensure updatedAt > lastReadAt
        Thread.sleep(forTimeInterval: 0.01)
        try db.endSession(pid: 1234, tool: .claude)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.unreadSessionIds.contains(session.id))
    }

    @Test("Read session that completes becomes unread again")
    @MainActor
    func readThenCompletedBecomesUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // Mark as read while idle
        try db.markSessionRead(id: session.id)

        // Ensure updatedAt > lastReadAt (avoid same-millisecond timestamps)
        Thread.sleep(forTimeInterval: 0.01)

        // Session completes (updates updatedAt)
        try db.endSession(pid: 1234, tool: .claude)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.unreadSessionIds.contains(session.id))
    }

    // MARK: - Mark All Read Tests

    @Test("requestMarkAllRead sets pending flag when unread sessions exist")
    @MainActor
    func requestMarkAllReadSetsPending() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1234, tool: .claude, ask: "hello", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(!vm.unreadSessionIds.isEmpty)

        vm.requestMarkAllRead()
        #expect(vm.pendingMarkAllRead == true)
    }

    @Test("requestMarkAllRead is no-op when no unread sessions")
    @MainActor
    func requestMarkAllReadNoopWhenAllRead() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.unreadSessionIds.isEmpty)

        vm.requestMarkAllRead()
        #expect(vm.pendingMarkAllRead == false)
    }

    @Test("confirmMarkAllRead clears all unread sessions")
    @MainActor
    func confirmMarkAllReadClearsUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let s1 = try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1111, tool: .claude, ask: "hello", status: .idle)

        let s2 = try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 2222, tool: .gemini, ask: "world", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.unreadSessionIds.contains(s1.id))
        #expect(vm.unreadSessionIds.contains(s2.id))

        vm.requestMarkAllRead()
        vm.confirmMarkAllRead()

        #expect(vm.unreadSessionIds.isEmpty)
        #expect(vm.pendingMarkAllRead == false)
    }

    @Test("cancelMarkAllRead resets pending flag")
    @MainActor
    func cancelMarkAllReadResetsPending() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1234, tool: .claude, ask: "hello", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.unreadSessionIds.contains(session.id))

        vm.requestMarkAllRead()
        #expect(vm.pendingMarkAllRead == true)

        vm.cancelMarkAllRead()
        #expect(vm.pendingMarkAllRead == false)
        #expect(vm.unreadSessionIds.contains(session.id))
    }

    @Test("Selection change clears pendingMarkAllRead")
    @MainActor
    func selectionChangeClearsPendingMarkAllRead() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 1111, tool: .claude, ask: "hello", status: .idle)

        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        Thread.sleep(forTimeInterval: 0.01)
        try db.updateSession(pid: 2222, tool: .gemini, ask: "world", status: .idle)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.requestMarkAllRead()
        #expect(vm.pendingMarkAllRead == true)

        vm.moveSelectionDown()
        #expect(vm.pendingMarkAllRead == false)
    }

    // MARK: - Recall Search Tests

    @Test("Recall state is clean on init")
    @MainActor
    func recallStateCleanOnInit() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)

        #expect(vm.recallResults.isEmpty)
        #expect(vm.isRecallSearching == false)
        #expect(vm.recallUnavailable == false)
    }

    @Test("exitSearch clears recall state")
    @MainActor
    func exitSearchClearsRecallState() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)

        vm.enterSearch()
        vm.appendSearchCharacter("t")
        vm.appendSearchCharacter("e")
        vm.appendSearchCharacter("s")
        vm.appendSearchCharacter("t")

        vm.exitSearch()

        #expect(vm.recallResults.isEmpty)
        #expect(vm.isRecallSearching == false)
        #expect(vm.isSearching == false)
        #expect(vm.searchQuery == "")
    }

    @Test("selectedRecallResult returns nil when not searching")
    @MainActor
    func selectedRecallResultNilWhenNotSearching() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.selectedRecallResult == nil)
    }

    @Test("selectedRecallResult returns nil when selection is in sessions section")
    @MainActor
    func selectedRecallResultNilInSessionSection() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        vm.enterSearch()

        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedRecallResult == nil)
    }

    @Test("totalResultCount equals session count when not searching")
    @MainActor
    func totalResultCountNoSearch() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.totalResultCount == 2)
    }

    @Test("moveToBottom respects totalResultCount when searching")
    @MainActor
    func moveToBottomWithSearch() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        vm.enterSearch()

        // Without recall results, bottom should be last session
        vm.moveToBottom()
        #expect(vm.selectedIndex == 1)
    }

    // MARK: - Session Lookup for Recall Results

    @Test("session(for:) finds matching active session")
    @MainActor
    func sessionForRecallResultFindsActive() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(
            tool: .claude, directory: "/tmp/project", pid: 1234,
            conversationId: "conv-abc"
        )

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        let result = RecallResult(
            agent: "claude", role: "user", sessionId: "conv-abc",
            project: "/tmp/project", timestamp: Date().timeIntervalSince1970,
            score: 0.9, resumeCmd: "claude --resume conv-abc", text: "test"
        )

        let found = vm.session(for: result)
        #expect(found?.id == session.id)
    }

    @Test("session(for:) finds matching inactive session")
    @MainActor
    func sessionForRecallResultFindsInactive() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(
            tool: .claude, directory: "/tmp/project", pid: 1234,
            conversationId: "conv-abc"
        )
        try db.endSession(pid: 1234, tool: .claude)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        let result = RecallResult(
            agent: "claude", role: "user", sessionId: "conv-abc",
            project: "/tmp/project", timestamp: Date().timeIntervalSince1970,
            score: 0.9, resumeCmd: "claude --resume conv-abc", text: "test"
        )

        let found = vm.session(for: result)
        #expect(found?.id == session.id)
    }

    @Test("session(for:) returns nil when no match")
    @MainActor
    func sessionForRecallResultNilWhenNoMatch() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/project", pid: 1234)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        let result = RecallResult(
            agent: "claude", role: "user", sessionId: "no-such-conv",
            project: "/tmp/project", timestamp: Date().timeIntervalSince1970,
            score: 0.9, resumeCmd: "claude --resume no-such-conv", text: "test"
        )

        #expect(vm.session(for: result) == nil)
    }
}
