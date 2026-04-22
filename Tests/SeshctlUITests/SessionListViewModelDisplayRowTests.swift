import Foundation
import Testing

import GRDB

@testable import SeshctlCore
@testable import SeshctlUI


@Suite("SessionListViewModelDisplayRow")
struct SessionListViewModelDisplayRowTests {
    private func makeIsolatedDefaults(_ name: String) -> (UserDefaults, String) {
        let suiteName = "seshctl.tests.displayrow.\(name).\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func makeRemote(
        id: String,
        title: String,
        repoUrl: String? = nil,
        branches: [String] = [],
        connectionStatus: String = "connected",
        lastEventAt: Date = Date(),
        unread: Bool = false
    ) -> RemoteClaudeCodeSession {
        RemoteClaudeCodeSession(
            id: id,
            title: title,
            model: "claude-opus-4-6[1m]",
            repoUrl: repoUrl,
            branches: branches,
            status: "active",
            workerStatus: "idle",
            connectionStatus: connectionStatus,
            lastEventAt: lastEventAt,
            createdAt: lastEventAt,
            unread: unread
        )
    }

    @Test("orderedRows merges local and remote by timestamp desc")
    @MainActor
    func orderedRowsMergesByTimestamp() throws {
        let db = try SeshctlDatabase.temporary()
        // Seed a local active session.
        try db.startSession(tool: .claude, directory: "/tmp/local-a", pid: 1234)

        // Seed a connected remote session with a later lastEventAt.
        let remoteEventAt = Date().addingTimeInterval(60)
        let remote = makeRemote(
            id: "cse_remote1",
            title: "remote session",
            lastEventAt: remoteEventAt
        )
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        let active = vm.activeRows
        #expect(active.count == 2)
        // Remote came later → first.
        #expect(active[0].id == "cse_remote1")
        // Local follows.
        if case .local(let s) = active[1] {
            #expect(s.pid == 1234)
        } else {
            Issue.record("Expected local row second; got \(active[1])")
        }
    }

    @Test("active split uses connection_status for remote")
    @MainActor
    func activeSplitByConnectionStatus() throws {
        let db = try SeshctlDatabase.temporary()
        let connected = makeRemote(id: "cse_conn", title: "connected", connectionStatus: "connected")
        let disconnected = makeRemote(
            id: "cse_disc", title: "disconnected",
            connectionStatus: "disconnected",
            lastEventAt: Date().addingTimeInterval(-60)
        )
        try db.upsertRemoteClaudeCodeSessions([connected, disconnected])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.activeRows.map(\.id) == ["cse_conn"])
        #expect(vm.recentRows.map(\.id) == ["cse_disc"])
    }

    @Test("filteredRows searches remote title, repo, and branches")
    @MainActor
    func filteredRowsSearchesRemoteFields() throws {
        let db = try SeshctlDatabase.temporary()
        let match = makeRemote(
            id: "cse_match",
            title: "Investigate cron error alert",
            repoUrl: "https://github.com/julo15/qbk-scheduler",
            branches: ["main"]
        )
        let noMatch = makeRemote(
            id: "cse_nomatch",
            title: "something else",
            repoUrl: "https://github.com/julo15/other",
            branches: ["feature-x"]
        )
        try db.upsertRemoteClaudeCodeSessions([match, noMatch])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()
        vm.enterSearch()

        // Match by title substring.
        vm.appendSearchCharacter("cron")
        #expect(vm.filteredRows.map(\.id) == ["cse_match"])

        // Match by repo short name.
        vm.clearSearchQuery()
        vm.appendSearchCharacter("qbk")
        #expect(vm.filteredRows.map(\.id) == ["cse_match"])

        // Match by branch name.
        vm.clearSearchQuery()
        vm.appendSearchCharacter("feature-x")
        #expect(vm.filteredRows.map(\.id) == ["cse_nomatch"])
    }

    @Test("treeGroups joins remote rows into matching local repo group")
    @MainActor
    func treeGroupsJoinRepoGroup() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        // Local session labeled as repo "qbk-scheduler".
        try db.startSession(tool: .claude, directory: "/tmp/qbk-scheduler", pid: 1)
        try db.dbPool.write { conn in
            try conn.execute(
                sql: "UPDATE sessions SET git_repo_name = ? WHERE pid = ?",
                arguments: ["qbk-scheduler", 1]
            )
        }

        // Remote session pointing at the same repo.
        let remote = makeRemote(
            id: "cse_qbk",
            title: "Scheduler session",
            repoUrl: "https://github.com/julo15/qbk-scheduler"
        )
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == "qbk-scheduler")
        #expect(groups[0].isRepo == true)
        #expect(groups[0].rows.count == 2)
        let ids = Set(groups[0].rows.map(\.id))
        #expect(ids.contains("cse_qbk"))
    }

    @Test("treeGroups creates 'Cloud — no repo' fallback")
    @MainActor
    func treeGroupsCloudNoRepoFallback() throws {
        let (defaults, suite) = makeIsolatedDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let db = try SeshctlDatabase.temporary()
        let remote = makeRemote(id: "cse_orphan", title: "Orphan session", repoUrl: nil)
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == SessionListViewModel.cloudNoRepoGroupName)
        #expect(groups[0].rows.count == 1)
        #expect(groups[0].rows.first?.id == "cse_orphan")
    }

    @Test("unreadSessionIds includes remote session with unread=true")
    @MainActor
    func unreadSessionIdsIncludesRemoteUnread() throws {
        let db = try SeshctlDatabase.temporary()
        let remote = makeRemote(id: "cse_unread", title: "pending", unread: true)
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        #expect(vm.unreadSessionIds.contains("cse_unread"))
    }

    @Test("requestKill on remote row no-ops and flips toast flag")
    @MainActor
    func requestKillOnRemoteFlipsToast() throws {
        let db = try SeshctlDatabase.temporary()
        let remote = makeRemote(id: "cse_kill", title: "cloud kill")
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        // Remote is selected by default (only row present).
        #expect(vm.selectedRow?.id == "cse_kill")
        #expect(vm.showedCloudKillToast == false)

        vm.requestKill()

        #expect(vm.pendingKillSessionId == nil)
        #expect(vm.showedCloudKillToast == true)

        // Acknowledging resets the flag.
        vm.acknowledgeCloudKillToast()
        #expect(vm.showedCloudKillToast == false)
    }

    @Test("requestKill on local row works as before")
    @MainActor
    func requestKillOnLocalStillWorks() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp/kill", pid: 5555)

        // Also seed a remote session, but keep selection on the local row.
        let remote = makeRemote(
            id: "cse_coexist",
            title: "coexist",
            lastEventAt: Date().addingTimeInterval(-120)
        )
        try db.upsertRemoteClaudeCodeSessions([remote])

        let vm = SessionListViewModel(database: db, enableGC: false)
        vm.refresh()

        // activeRows is timestamp-desc; the local row is newer, so it's first.
        #expect(vm.selectedIndex == 0)
        guard case .local(let selected) = vm.selectedRow else {
            Issue.record("Expected local row selected")
            return
        }
        #expect(selected.id == session.id)

        vm.requestKill()

        #expect(vm.pendingKillSessionId == session.id)
        #expect(vm.showedCloudKillToast == false)
    }

    @Test("repo short name extracts last path component without .git")
    func repoShortNameExtraction() {
        #expect(DisplayRow.repoShortName(from: "https://github.com/julo15/qbk-scheduler") == "qbk-scheduler")
        #expect(DisplayRow.repoShortName(from: "https://github.com/julo15/qbk-scheduler.git") == "qbk-scheduler")
        #expect(DisplayRow.repoShortName(from: nil) == nil)
    }

    // MARK: - Source filter

    @Test("cycleSourceFilter rotates all -> localOnly -> remoteOnly -> all")
    @MainActor
    func cycleSourceFilterRotates() throws {
        let db = try SeshctlDatabase.temporary()
        let (defaults, _) = makeIsolatedDefaults("cycle")
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)

        #expect(vm.sourceFilter == .all)
        vm.cycleSourceFilter()
        #expect(vm.sourceFilter == .localOnly)
        vm.cycleSourceFilter()
        #expect(vm.sourceFilter == .remoteOnly)
        vm.cycleSourceFilter()
        #expect(vm.sourceFilter == .all)
    }

    @Test("localOnly filter hides remote rows")
    @MainActor
    func localOnlyHidesRemote() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/local", pid: 1111)
        try db.upsertRemoteClaudeCodeSessions([makeRemote(id: "cse_hidden", title: "remote")])

        let (defaults, _) = makeIsolatedDefaults("localonly")
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        #expect(vm.orderedRows.count == 2)

        vm.cycleSourceFilter()  // all -> localOnly
        let ids = vm.orderedRows.map(\.id)
        #expect(ids.count == 1)
        #expect(!ids.contains("cse_hidden"))
    }

    @Test("remoteOnly filter hides local rows")
    @MainActor
    func remoteOnlyHidesLocal() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/local", pid: 2222)
        try db.upsertRemoteClaudeCodeSessions([makeRemote(id: "cse_visible", title: "remote")])

        let (defaults, _) = makeIsolatedDefaults("remoteonly")
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        vm.cycleSourceFilter()  // -> localOnly
        vm.cycleSourceFilter()  // -> remoteOnly
        #expect(vm.orderedRows.map(\.id) == ["cse_visible"])
    }

    @Test("sourceFilter persists across view-model instances")
    @MainActor
    func sourceFilterPersists() throws {
        let db = try SeshctlDatabase.temporary()
        let (defaults, _) = makeIsolatedDefaults("persist")

        let vm1 = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm1.cycleSourceFilter()  // -> localOnly
        #expect(vm1.sourceFilter == .localOnly)

        let vm2 = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        #expect(vm2.sourceFilter == .localOnly)
    }

    @Test("cycle always snaps selection to index 0")
    @MainActor
    func cycleSnapsToTop() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 3001)
        try db.startSession(tool: .claude, directory: "/tmp/b", pid: 3002)
        try db.upsertRemoteClaudeCodeSessions([
            makeRemote(id: "cse_1", title: "r1", lastEventAt: Date().addingTimeInterval(-60)),
            makeRemote(id: "cse_2", title: "r2", lastEventAt: Date().addingTimeInterval(-120))
        ])

        let (defaults, _) = makeIsolatedDefaults("snap")
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        // Move off the top so we can verify the snap.
        vm.moveSelectionBy(2)
        #expect(vm.selectedIndex == 2)

        vm.cycleSourceFilter()  // all -> localOnly: should snap to index 0.
        #expect(vm.selectedIndex == 0)

        vm.moveSelectionBy(1)
        #expect(vm.selectedIndex == 1)

        vm.cycleSourceFilter()  // localOnly -> remoteOnly: again snap to 0.
        #expect(vm.selectedIndex == 0)
    }

    @Test("cycle to an empty ordering sets selectedIndex to -1")
    @MainActor
    func cycleToEmptyOrderingClearsSelection() throws {
        let db = try SeshctlDatabase.temporary()
        // No locals, one remote. Cycling to localOnly leaves zero rows.
        try db.upsertRemoteClaudeCodeSessions([makeRemote(id: "cse_lonely", title: "r")])

        let (defaults, _) = makeIsolatedDefaults("empty")
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()
        #expect(vm.selectedIndex == 0)

        vm.cycleSourceFilter()  // all -> localOnly: nothing local.
        #expect(vm.orderedRows.isEmpty)
        #expect(vm.selectedIndex == -1)
    }
}
