import Foundation
import Testing

import GRDB

@testable import SeshctlCore
@testable import SeshctlUI


@Suite("SessionTreeGrouping")
struct SessionTreeGroupingTests {
    private func makeDefaults(_ name: String = UUID().uuidString) -> (UserDefaults, String) {
        let suiteName = "seshctl.tests.\(name).\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func setRepo(
        _ db: SeshctlDatabase, pid: Int, repo: String?, branch: String? = nil
    ) throws {
        try db.dbPool.write { conn in
            try conn.execute(
                sql: "UPDATE sessions SET git_repo_name = ?, git_branch = ? WHERE pid = ?",
                arguments: [repo, branch, pid]
            )
        }
    }

    @Test("Sessions sharing gitRepoName group under that repo")
    @MainActor
    func sharedRepoGroups() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/ios-2", pid: 1)
        try db.startSession(tool: .gemini, directory: "/tmp/ios-2/sub", pid: 2)
        try setRepo(db, pid: 1, repo: "ios-2")
        try setRepo(db, pid: 2, repo: "ios-2")

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == "ios-2")
        #expect(groups[0].isRepo == true)
        #expect(groups[0].sessions.count == 2)
    }

    @Test("Session without gitRepoName groups by directory lastPathComponent")
    @MainActor
    func nonRepoGroupsByDir() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/Users/julianlo/scratch/foo", pid: 1)

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == "foo")
        #expect(groups[0].isRepo == false)
        #expect(groups[0].sessions.count == 1)
    }

    @Test("Groups sort alphabetical case-insensitive; sessions by updatedAt desc")
    @MainActor
    func sortingOrder() throws {
        let db = try SeshctlDatabase.temporary()
        // Three repos: "Bravo", "alpha", "Charlie"
        try db.startSession(tool: .claude, directory: "/tmp/Bravo", pid: 1)
        try db.startSession(tool: .claude, directory: "/tmp/alpha", pid: 2)
        try db.startSession(tool: .claude, directory: "/tmp/Charlie", pid: 3)
        try setRepo(db, pid: 1, repo: "Bravo")
        try setRepo(db, pid: 2, repo: "alpha")
        try setRepo(db, pid: 3, repo: "Charlie")

        // Two sessions in alpha: put the second with a newer updatedAt by updating it later.
        try db.startSession(tool: .gemini, directory: "/tmp/alpha", pid: 4)
        try setRepo(db, pid: 4, repo: "alpha")
        Thread.sleep(forTimeInterval: 0.02)
        try db.updateSession(pid: 4, tool: .gemini, status: .working)

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.map(\.name) == ["alpha", "Bravo", "Charlie"])

        let alpha = groups[0]
        #expect(alpha.sessions.count == 2)
        // Newer-updated session (pid 4) first
        #expect(alpha.sessions[0].pid == 4)
        #expect(alpha.sessions[1].pid == 2)
    }

    @Test("Non-repo group named X and repo group named X are distinct entries")
    @MainActor
    func repoAndNonRepoSameNameDistinct() throws {
        let db = try SeshctlDatabase.temporary()
        // Repo-backed "foo"
        try db.startSession(tool: .claude, directory: "/tmp/foo", pid: 1)
        try setRepo(db, pid: 1, repo: "foo")
        // Non-repo "foo" (directory lastPathComponent = foo, no gitRepoName)
        try db.startSession(tool: .gemini, directory: "/Users/x/scratch/foo", pid: 2)

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 2)
        // Repo group ties-break to first
        #expect(groups[0].name == "foo")
        #expect(groups[0].isRepo == true)
        #expect(groups[1].name == "foo")
        #expect(groups[1].isRepo == false)
    }

    @Test("Only active sessions appear in treeGroups")
    @MainActor
    func activeOnlyInTree() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/alpha", pid: 1)
        try setRepo(db, pid: 1, repo: "alpha")
        try db.startSession(tool: .gemini, directory: "/tmp/beta", pid: 2)
        try setRepo(db, pid: 2, repo: "beta")
        try db.endSession(pid: 2, tool: .gemini)

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let groups = vm.treeGroups
        #expect(groups.count == 1)
        #expect(groups[0].name == "alpha")
        #expect(vm.treeOrderedSessions.count == 1)
    }

    @Test("treeOrderedSessions flattens groups; headers not included")
    @MainActor
    func treeOrderedFlatten() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/alpha", pid: 1)
        try setRepo(db, pid: 1, repo: "alpha")
        try db.startSession(tool: .claude, directory: "/tmp/alpha", pid: 2)
        try setRepo(db, pid: 2, repo: "alpha")
        try db.startSession(tool: .gemini, directory: "/tmp/beta", pid: 3)
        try setRepo(db, pid: 3, repo: "beta")

        let (defaults, suite) = makeDefaults(#function)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let vm = SessionListViewModel(database: db, enableGC: false, defaults: defaults)
        vm.refresh()

        let ordered = vm.treeOrderedSessions
        #expect(ordered.count == 3)
        // alpha group (2 sessions) then beta (1)
        let groups = vm.treeGroups
        let expected = groups.flatMap(\.sessions).map(\.id)
        #expect(ordered.map(\.id) == expected)
    }
}
