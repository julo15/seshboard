import Foundation
import Testing

@testable import SeshctlCore

@Suite("RemoteClaudeCodeSession")
struct RemoteClaudeCodeSessionTests {
    // Fixed reference dates so timestamp ordering is deterministic
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_700_001_000)
    private static let t2 = Date(timeIntervalSince1970: 1_700_002_000)
    private static let t3 = Date(timeIntervalSince1970: 1_700_003_000)

    private func makeSession(
        id: String,
        title: String = "Test session",
        model: String = "claude-opus-4-6[1m]",
        repoUrl: String? = "https://github.com/julo15/qbk-scheduler",
        branches: [String] = ["main"],
        status: String = "active",
        workerStatus: String = "idle",
        connectionStatus: String = "connected",
        lastEventAt: Date = RemoteClaudeCodeSessionTests.t0,
        createdAt: Date = RemoteClaudeCodeSessionTests.t0,
        unread: Bool = false
    ) -> RemoteClaudeCodeSession {
        RemoteClaudeCodeSession(
            id: id,
            title: title,
            model: model,
            repoUrl: repoUrl,
            branches: branches,
            status: status,
            workerStatus: workerStatus,
            connectionStatus: connectionStatus,
            lastEventAt: lastEventAt,
            createdAt: createdAt,
            unread: unread
        )
    }

    @Test("v10 migration creates the remote_claude_code_sessions table")
    func v10MigrationCreatesTable() throws {
        let db = try SeshctlDatabase.temporary()
        // If the migration didn't run, listing would throw (no such table).
        let rows = try db.listRemoteClaudeCodeSessions()
        #expect(rows.isEmpty)
    }

    @Test("upsert round-trips all fields")
    func upsertRoundTripsAllFields() throws {
        let db = try SeshctlDatabase.temporary()
        let session = makeSession(
            id: "cse_roundtrip",
            title: "Investigate cron error rate check alert",
            model: "claude-opus-4-6[1m]",
            repoUrl: "https://github.com/julo15/qbk-scheduler",
            branches: ["main"],
            status: "active",
            workerStatus: "idle",
            connectionStatus: "connected",
            lastEventAt: Self.t1,
            createdAt: Self.t0,
            unread: true
        )

        try db.upsertRemoteClaudeCodeSessions([session])
        let fetched = try db.listRemoteClaudeCodeSessions()

        #expect(fetched.count == 1)
        let got = fetched[0]
        #expect(got.id == "cse_roundtrip")
        #expect(got.title == "Investigate cron error rate check alert")
        #expect(got.model == "claude-opus-4-6[1m]")
        #expect(got.repoUrl == "https://github.com/julo15/qbk-scheduler")
        #expect(got.branches == ["main"])
        #expect(got.status == "active")
        #expect(got.workerStatus == "idle")
        #expect(got.connectionStatus == "connected")
        #expect(got.lastEventAt == Self.t1)
        #expect(got.createdAt == Self.t0)
        #expect(got.unread == true)
    }

    @Test("upsert replaces the set — rows not in input are deleted")
    func upsertReplacesSet() throws {
        let db = try SeshctlDatabase.temporary()

        let a = makeSession(id: "cse_A", lastEventAt: Self.t0)
        let b = makeSession(id: "cse_B", lastEventAt: Self.t1)
        let c = makeSession(id: "cse_C", lastEventAt: Self.t2)
        try db.upsertRemoteClaudeCodeSessions([a, b, c])

        // Verify initial state
        let first = try db.listRemoteClaudeCodeSessions()
        #expect(first.count == 3)

        // Replace: keep B, add D, drop A and C
        let bUpdated = makeSession(id: "cse_B", lastEventAt: Self.t1)
        let d = makeSession(id: "cse_D", lastEventAt: Self.t3)
        try db.upsertRemoteClaudeCodeSessions([bUpdated, d])

        let after = try db.listRemoteClaudeCodeSessions()
        #expect(after.count == 2)
        // Ordered by last_event_at DESC → D (t3) then B (t1)
        #expect(after.map(\.id) == ["cse_D", "cse_B"])
    }

    @Test("upsert updates existing row by id")
    func upsertUpdatesExistingById() throws {
        let db = try SeshctlDatabase.temporary()

        let old = makeSession(id: "cse_same", title: "Old")
        try db.upsertRemoteClaudeCodeSessions([old])

        let updated = makeSession(id: "cse_same", title: "New")
        try db.upsertRemoteClaudeCodeSessions([updated])

        let fetched = try db.listRemoteClaudeCodeSessions()
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "New")
    }

    @Test("clear empties the table")
    func clearEmptiesTable() throws {
        let db = try SeshctlDatabase.temporary()

        try db.upsertRemoteClaudeCodeSessions([
            makeSession(id: "cse_1"),
            makeSession(id: "cse_2"),
        ])
        #expect(try db.listRemoteClaudeCodeSessions().count == 2)

        try db.clearRemoteClaudeCodeSessions()
        #expect(try db.listRemoteClaudeCodeSessions().isEmpty)
    }

    @Test("branches round-trip multi-value in order")
    func branchesRoundTripMultiValue() throws {
        let db = try SeshctlDatabase.temporary()
        let session = makeSession(id: "cse_branches", branches: ["main", "feature/x"])
        try db.upsertRemoteClaudeCodeSessions([session])

        let fetched = try db.listRemoteClaudeCodeSessions()
        #expect(fetched.count == 1)
        #expect(fetched[0].branches == ["main", "feature/x"])
    }

    @Test("branches round-trip empty")
    func branchesRoundTripEmpty() throws {
        let db = try SeshctlDatabase.temporary()
        let session = makeSession(id: "cse_empty_branches", branches: [])
        try db.upsertRemoteClaudeCodeSessions([session])

        let fetched = try db.listRemoteClaudeCodeSessions()
        #expect(fetched.count == 1)
        #expect(fetched[0].branches == [])
    }

    @Test("webUrl is computed from id")
    func webUrlComputed() {
        let session = makeSession(id: "cse_abc123")
        #expect(session.webUrl.absoluteString == "https://claude.ai/code/session/cse_abc123")
    }
}
