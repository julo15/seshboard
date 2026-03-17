import Foundation
import Testing

@testable import SeshboardCore
@testable import SeshboardUI


@Suite("SessionListViewModel")
struct SessionListViewModelTests {
    @Test("Refresh loads sessions from database")
    @MainActor
    func refreshLoadsSessions() throws {
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        #expect(vm.selectedIndex == 0)
    }

    @Test("Move selection down")
    @MainActor
    func moveDown() throws {
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1)

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        vm.moveSelectionUp()
        #expect(vm.selectedIndex == 0)
    }

    @Test("Selected session returns correct session")
    @MainActor
    func selectedSession() throws {
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        #expect(vm.selectedSession == nil)
    }

    @Test("Reset selection goes back to 0")
    @MainActor
    func resetSelection() throws {
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
        let db = try SeshboardDatabase.temporary()
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
}
