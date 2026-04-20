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

        #expect(vm.localActiveSessions.count == 1)
        #expect(vm.localActiveSessions[0].tool == .claude)
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

        #expect(vm.localRecentSessions.count == 1)
        #expect(vm.localRecentSessions[0].tool == .gemini)
    }

    @Test("Empty database shows no sessions")
    @MainActor
    func emptySessions() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.sessions.isEmpty)
        #expect(vm.localActiveSessions.isEmpty)
        #expect(vm.localRecentSessions.isEmpty)
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

        #expect(vm.localActiveSessions.count == 1)
        #expect(vm.localActiveSessions[0].status == .working)
    }

    @Test("Stale sessions appear in recent list")
    @MainActor
    func staleIsRecent() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 99999)
        _ = try db.gc(isProcessAlive: { _ in false })

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.localActiveSessions.isEmpty)
        #expect(vm.localRecentSessions.count == 1)
        #expect(vm.localRecentSessions[0].status == .stale)
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
        let target = vm.localOrderedSessions[1]
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

        let target = vm.localOrderedSessions[1]
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
        let gemini = vm.localOrderedSessions.first { $0.tool == .gemini }!
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

        let ordered = vm.localOrderedSessions
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

    // MARK: - deleteSearchWord Tests

    @Test("deleteSearchWord removes last word")
    @MainActor
    func deleteSearchWordRemovesLastWord() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.appendSearchCharacter("hello world")
        vm.deleteSearchWord()
        #expect(vm.searchQuery == "hello ")
    }

    @Test("deleteSearchWord removes trailing whitespace then word")
    @MainActor
    func deleteSearchWordTrailingWhitespace() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.appendSearchCharacter("hello   ")
        vm.deleteSearchWord()
        #expect(vm.searchQuery == "")
    }

    @Test("deleteSearchWord on single word clears query")
    @MainActor
    func deleteSearchWordSingleWord() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.appendSearchCharacter("hello")
        vm.deleteSearchWord()
        #expect(vm.searchQuery == "")
    }

    @Test("deleteSearchWord on empty query exits search")
    @MainActor
    func deleteSearchWordEmptyExitsSearch() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.deleteSearchWord()
        #expect(!vm.isSearching)
    }

    // MARK: - clearSearchQuery Tests

    @Test("clearSearchQuery clears the query but stays in search mode")
    @MainActor
    func clearSearchQueryClears() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.appendSearchCharacter("hello")
        vm.clearSearchQuery()
        #expect(vm.searchQuery == "")
        #expect(vm.isSearching)
        #expect(vm.selectedIndex == 0)
    }

    // MARK: - Multi-character append (paste) Tests

    @Test("appendSearchCharacter with multi-character string")
    @MainActor
    func appendMultiCharString() throws {
        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.enterSearch()
        vm.appendSearchCharacter("hello world")
        #expect(vm.searchQuery == "hello world")
        #expect(vm.selectedIndex == 0)
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
        #expect(vm.recallIndexingDone == nil)
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
        #expect(vm.recallIndexingDone == nil)
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

    // MARK: - Tree Mode / View Toggle Tests

    private func makeIsolatedDefaults(_ name: String) -> (UserDefaults, String) {
        let suiteName = "seshctl.tests.\(name).\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func setRepo(
        _ db: SeshctlDatabase, pid: Int, repo: String?
    ) throws {
        try db.dbPool.write { conn in
            try conn.execute(
                sql: "UPDATE sessions SET git_repo_name = ? WHERE pid = ?",
                arguments: [repo, pid]
            )
        }
    }

    @Test("toggleViewMode preserves selected session by id across modes")
    @MainActor
    func toggleViewModePreservesSelection() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/alpha", pid: 1)
        try setRepo(db, pid: 1, repo: "alpha")
        try db.startSession(tool: .claude, directory: "/tmp/beta", pid: 2)
        try setRepo(db, pid: 2, repo: "beta")
        try db.startSession(tool: .gemini, directory: "/tmp/gamma", pid: 3)
        try setRepo(db, pid: 3, repo: "gamma")

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        // List mode default: pick the 2nd session.
        vm.selectedIndex = 1
        let targetId = vm.selectedSession?.id
        #expect(targetId != nil)

        // Toggle to tree mode.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == true)
        #expect(vm.selectedSession?.id == targetId)

        // Toggle back.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == false)
        #expect(vm.selectedSession?.id == targetId)
    }

    @Test("toggleViewMode falls back to index 0 when session missing from new ordering")
    @MainActor
    func toggleViewModeFallbackWhenMissing() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        // Active session.
        try db.startSession(tool: .claude, directory: "/tmp/active", pid: 1)
        try setRepo(db, pid: 1, repo: "active")
        // Recent (completed) session.
        try db.startSession(tool: .gemini, directory: "/tmp/recent", pid: 2)
        try setRepo(db, pid: 2, repo: "recent")
        try db.endSession(pid: 2, tool: .gemini)

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        // In list mode, recent session is at index 1 (active first, then recent).
        // Pick the recent session.
        let recentIndex = vm.localOrderedSessions.firstIndex { !$0.isActive }!
        vm.selectedIndex = recentIndex

        // Toggle to tree — recents are excluded, so the selection should fall back to 0.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == true)
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedSession?.isActive == true)
    }

    @Test("toggleViewMode sets selectedIndex to -1 when new ordering is empty")
    @MainActor
    func toggleViewModeEmptyNextOrdering() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        // Only a recent session; active list is empty.
        try db.startSession(tool: .claude, directory: "/tmp/r", pid: 1)
        try db.endSession(pid: 1, tool: .claude)

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        // Select the recent session in list mode.
        vm.selectedIndex = 0
        #expect(vm.selectedSession != nil)

        // Toggle to tree — no active sessions, tree is empty.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == true)
        #expect(vm.selectedIndex == -1)
        #expect(vm.selectedSession == nil)
    }

    @Test("isTreeMode round-trips through injected UserDefaults")
    @MainActor
    func isTreeModePersists() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()

        let vm1 = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        #expect(vm1.isTreeMode == false)
        vm1.isTreeMode = true

        // New viewmodel with the same store — should read the persisted value.
        let vm2 = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        #expect(vm2.isTreeMode == true)

        vm2.isTreeMode = false
        let vm3 = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        #expect(vm3.isTreeMode == false)
    }

    @Test("Entering search from tree mode preserves isTreeMode across search")
    @MainActor
    func enterSearchFromTreeMode() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        vm.isTreeMode = true

        // Simulate AppDelegate's `/` flow: just enter search; tree mode must
        // not be mutated (the view gates on `isTreeMode && !isSearching`).
        vm.enterSearch()

        #expect(vm.isTreeMode == true)
        #expect(vm.isSearching == true)

        // Exiting search leaves tree mode intact.
        vm.exitSearch()
        #expect(vm.isTreeMode == true)
        #expect(vm.isSearching == false)

        // UserDefaults still reflects tree mode (no silent write-through).
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)
    }

    // MARK: - Inbox-aware reset on panel open

    @Test("applyInboxAwareResetIfNeeded does nothing in list mode")
    @MainActor
    func inboxResetNoOpInListMode() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        #expect(vm.isTreeMode == false)

        // Even with a long-elapsed lastClosedAt, list mode should not be touched.
        let now = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: Date(timeIntervalSince1970: 1_000))
        let flipped = vm.applyInboxAwareResetIfNeeded(now: now)
        #expect(flipped == false)
        #expect(vm.isTreeMode == false)
    }

    @Test("applyInboxAwareResetIfNeeded does nothing within burst window (<= 10s since lastClosedAt)")
    @MainActor
    func inboxResetNoOpWithinBurstWindow() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true

        let close = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: close)

        // Exactly at the boundary (10s): still within window.
        let atBoundary = close.addingTimeInterval(10)
        #expect(vm.applyInboxAwareResetIfNeeded(now: atBoundary) == false)
        #expect(vm.isTreeMode == true)

        // Well within window.
        let within = close.addingTimeInterval(3)
        #expect(vm.applyInboxAwareResetIfNeeded(now: within) == false)
        #expect(vm.isTreeMode == true)
    }

    @Test("applyInboxAwareResetIfNeeded flips to list mode when > 10s elapsed, without persisting")
    @MainActor
    func inboxResetFlipsTransientlyAfterBurstWindow() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)

        let close = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: close)

        // 10.001s elapsed — just past the boundary.
        let after = close.addingTimeInterval(10.001)
        let flipped = vm.applyInboxAwareResetIfNeeded(now: after)
        #expect(flipped == true)
        #expect(vm.isTreeMode == false)
        // The critical invariant: persisted tree-mode preference is untouched.
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)
    }

    @Test("recordPanelClose writes lastClosedAt to defaults")
    @MainActor
    func recordPanelCloseWritesDefaults() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)

        let now = Date(timeIntervalSince1970: 1_234_567.5)
        vm.recordPanelClose(now: now)
        #expect(defaults.double(forKey: "seshctl.lastClosedAt") == 1_234_567.5)
    }

    @Test("After a transient flip, toggleViewMode restores tree mode AND persists it")
    @MainActor
    func toggleViewModeAfterTransientFlipPersists() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        vm.isTreeMode = true
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)

        let close = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: close)
        let flipped = vm.applyInboxAwareResetIfNeeded(now: close.addingTimeInterval(60))
        #expect(flipped == true)
        #expect(vm.isTreeMode == false)
        // Persistence unchanged by the transient flip.
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)

        // User presses `v` — goes back to tree mode and this time persistence writes.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == true)
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)

        // Press `v` again — writes list mode this time.
        vm.toggleViewMode()
        #expect(vm.isTreeMode == false)
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == false)
    }

    @Test("First open after install (no lastClosedAt stored) flips to list when in tree mode")
    @MainActor
    func inboxResetFirstOpenAfterInstall() throws {
        // Documents the edge case: with no stored `lastClosedAt`, the default
        // value read from UserDefaults is 0 (epoch), so `now - 0` is always
        // far greater than the 10s burst window, and we treat the open as a
        // fresh inbox glance and flip to list mode.
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true
        #expect(defaults.object(forKey: "seshctl.lastClosedAt") == nil)

        let flipped = vm.applyInboxAwareResetIfNeeded()
        #expect(flipped == true)
        #expect(vm.isTreeMode == false)
        // Persistence untouched.
        #expect(defaults.bool(forKey: "seshctl.isTreeMode") == true)
    }

    @Test("applyInboxAwareResetIfNeeded preserves selectedIndex across the flip")
    @MainActor
    func inboxResetPreservesSelectedIndex() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        for i in 1...5 { try db.startSession(tool: .claude, directory: "/tmp/\(i)", pid: i) }

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true
        vm.refresh()

        let middle = 2
        vm.selectedIndex = middle

        let close = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: close)
        let after = close.addingTimeInterval(60)
        let flipped = vm.applyInboxAwareResetIfNeeded(now: after, burstWindow: 10)
        #expect(flipped == true)
        // selectedIndex is intentionally preserved by the transient flip.
        // (The session under it may differ because orderedSessions changed shape.)
        #expect(vm.selectedIndex == middle)
    }

    @Test("applyInboxAwareResetIfNeeded flips just past 10.0s boundary")
    @MainActor
    func inboxResetFlipsJustPastBoundary() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true

        let close = Date(timeIntervalSince1970: 1_000_000)
        vm.recordPanelClose(now: close)

        // Just past 10.0s — float-clarity boundary check.
        let justPast = close.addingTimeInterval(10.0001)
        let flipped = vm.applyInboxAwareResetIfNeeded(now: justPast)
        #expect(flipped == true)
        #expect(vm.isTreeMode == false)
    }

    @Test("applyInboxAwareResetIfNeeded does not flip on negative elapsed (clock skew)")
    @MainActor
    func inboxResetNoFlipOnNegativeElapsed() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.isTreeMode = true

        // Simulate a clock skew: lastClosedAt is in the future relative to now.
        let close = Date(timeIntervalSince1970: 2_000_000)
        vm.recordPanelClose(now: close)
        let now = Date(timeIntervalSince1970: 1_000_000) // now < lastClosedAt

        let flipped = vm.applyInboxAwareResetIfNeeded(now: now)
        #expect(flipped == false)
        #expect(vm.isTreeMode == true)
    }

    @Test("toggleViewMode clears pendingKillSessionId and pendingMarkAllRead")
    @MainActor
    func toggleViewModeClearsPendingState() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let sessionId = vm.localOrderedSessions.first!.id
        vm.pendingKillSessionId = sessionId
        vm.pendingMarkAllRead = true

        vm.toggleViewMode()

        #expect(vm.pendingKillSessionId == nil)
        #expect(vm.pendingMarkAllRead == false)
    }

    // MARK: - Sentinel preservation (empty ordering) Tests

    @Test("Move/page/gg/G preserve selectedIndex = -1 when ordering is empty")
    @MainActor
    func sentinelPreservedOnEmpty() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        #expect(vm.localOrderedSessions.isEmpty)

        vm.selectedIndex = -1

        vm.moveSelectionUp()
        #expect(vm.selectedIndex == -1)

        vm.moveSelectionDown()
        #expect(vm.selectedIndex == -1)

        vm.moveSelectionBy(-10)
        #expect(vm.selectedIndex == -1)

        vm.moveSelectionBy(10)
        #expect(vm.selectedIndex == -1)

        vm.moveToTop()
        #expect(vm.selectedIndex == -1)

        vm.moveToBottom()
        #expect(vm.selectedIndex == -1)
    }

    // MARK: - Group jump (h/l) tests

    /// Build a tree-mode viewmodel with three groups:
    ///   alpha [session 1]
    ///   beta  [session 2, session 3]
    ///   gamma [session 4]
    @MainActor
    private func makeTreeViewModelWithGroups(
        _ name: String
    ) throws -> (SessionListViewModel, String) {
        let (defaults, suite) = makeIsolatedDefaults(name)
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/alpha/a1", pid: 1)
        try setRepo(db, pid: 1, repo: "alpha")
        try db.startSession(tool: .claude, directory: "/tmp/beta/b1", pid: 2)
        try setRepo(db, pid: 2, repo: "beta")
        try db.startSession(tool: .claude, directory: "/tmp/beta/b2", pid: 3)
        try setRepo(db, pid: 3, repo: "beta")
        try db.startSession(tool: .gemini, directory: "/tmp/gamma/g1", pid: 4)
        try setRepo(db, pid: 4, repo: "gamma")

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        vm.isTreeMode = true
        return (vm, suite)
    }

    @Test("jumpToNextGroup moves selection to first session of next group")
    @MainActor
    func jumpToNextGroupMovesToNextGroup() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // Start at alpha's only session (index 0).
        vm.selectedIndex = 0
        vm.jumpToNextGroup()
        // Next group is beta; its first session is at index 1.
        #expect(vm.selectedIndex == 1)

        // From the second session of beta (index 2), next group is gamma at index 3.
        vm.selectedIndex = 2
        vm.jumpToNextGroup()
        #expect(vm.selectedIndex == 3)
    }

    @Test("jumpToNextGroup at last group is a no-op")
    @MainActor
    func jumpToNextGroupAtLastGroupNoOp() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // gamma is the last group, sole session at index 3.
        vm.selectedIndex = 3
        vm.jumpToNextGroup()
        #expect(vm.selectedIndex == 3)
    }

    @Test("jumpToPreviousGroup from mid-group jumps to first session of current group")
    @MainActor
    func jumpToPreviousGroupFromMidGroup() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // beta's second session is at index 2; jumping back should land on beta's first (index 1).
        vm.selectedIndex = 2
        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == 1)
    }

    @Test("jumpToPreviousGroup from first session of group jumps to previous group")
    @MainActor
    func jumpToPreviousGroupFromGroupStart() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // beta's first session is at index 1; jumping back should land on alpha's first (index 0).
        vm.selectedIndex = 1
        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == 0)
    }

    @Test("jumpToPreviousGroup at first group is a no-op")
    @MainActor
    func jumpToPreviousGroupAtFirstGroupNoOp() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        vm.selectedIndex = 0
        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == 0)
    }

    @Test("jumpToNextGroup and jumpToPreviousGroup preserve -1 sentinel on empty tree")
    @MainActor
    func jumpGroupPreservesSentinel() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        vm.isTreeMode = true
        vm.selectedIndex = -1

        vm.jumpToNextGroup()
        #expect(vm.selectedIndex == -1)

        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == -1)
    }

    @Test("jumpToNextGroup with no selection is a no-op")
    @MainActor
    func jumpToNextGroupWithNoSelectionIsNoOp() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // Tree is non-empty, but no selection is active.
        vm.selectedIndex = -1
        vm.jumpToNextGroup()
        #expect(vm.selectedIndex == -1)
    }

    @Test("jumpToPreviousGroup with no selection is a no-op")
    @MainActor
    func jumpToPreviousGroupWithNoSelectionIsNoOp() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // Tree is non-empty, but no selection is active.
        vm.selectedIndex = -1
        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == -1)
    }

    @Test("jumpToNextGroup and jumpToPreviousGroup are no-ops in list mode")
    @MainActor
    func jumpGroupNoOpInListMode() throws {
        let (vm, suite) = try makeTreeViewModelWithGroups(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        vm.isTreeMode = false
        vm.selectedIndex = 2
        vm.jumpToNextGroup()
        #expect(vm.selectedIndex == 2)

        vm.jumpToPreviousGroup()
        #expect(vm.selectedIndex == 2)
    }
}
