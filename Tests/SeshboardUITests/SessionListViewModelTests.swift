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

        let vm = SessionListViewModel(database: db)
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

        let vm = SessionListViewModel(database: db)
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

        let vm = SessionListViewModel(database: db)
        vm.refresh()

        #expect(vm.recentSessions.count == 1)
        #expect(vm.recentSessions[0].tool == .gemini)
    }

    @Test("Empty database shows no sessions")
    @MainActor
    func emptySessions() throws {
        let db = try SeshboardDatabase.temporary()
        let vm = SessionListViewModel(database: db)
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
        let vm = SessionListViewModel(database: db)

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

        let vm = SessionListViewModel(database: db)
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

        let vm = SessionListViewModel(database: db)
        vm.refresh()

        #expect(vm.activeSessions.isEmpty)
        #expect(vm.recentSessions.count == 1)
        #expect(vm.recentSessions[0].status == .stale)
    }
}
