import Foundation
import GRDB

public struct SeshboardDatabase: Sendable {
    private let dbPool: DatabasePool

    /// Opens (or creates) the database at the given path with WAL mode.
    public init(path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode for concurrent read/write safety
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbPool = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    /// Creates a temporary file-backed database for testing.
    public static func temporary() throws -> SeshboardDatabase {
        let path = NSTemporaryDirectory() + "seshboard-test-\(UUID().uuidString).db"
        return try SeshboardDatabase(path: path)
    }

    private init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_sessions") { db in
            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("conversation_id", .text)
                t.column("tool", .text).notNull()
                t.column("directory", .text).notNull()
                t.column("last_ask", .text)
                t.column("status", .text).notNull().defaults(to: "idle")
                t.column("pid", .integer)
                t.column("window_id", .text)
                t.column("started_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(
                index: "idx_sessions_updated_at", on: "sessions",
                columns: ["updated_at"])
            try db.create(
                index: "idx_sessions_status", on: "sessions",
                columns: ["status"])
            try db.create(
                index: "idx_sessions_conversation", on: "sessions",
                columns: ["conversation_id"])
            try db.create(
                index: "idx_sessions_pid_tool", on: "sessions",
                columns: ["pid", "tool"])
        }

        migrator.registerMigration("v2_add_host_app") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "host_app_bundle_id", .text)
                t.add(column: "host_app_name", .text)
            }
        }

        migrator.registerMigration("v3_add_transcript_path") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "transcript_path", .text)
            }
        }

        try migrator.migrate(dbPool)
    }

    // MARK: - Helpers

    private static let activeStatusFilter =
        Column("status") == SessionStatus.idle.rawValue
        || Column("status") == SessionStatus.working.rawValue
        || Column("status") == SessionStatus.waiting.rawValue

    // MARK: - Session Operations

    /// Find the active session for a given pid+tool.
    public func findActiveSession(pid: Int, tool: SessionTool) throws -> Session? {
        try dbPool.read { db in
            try Session
                .filter(Column("pid") == pid)
                .filter(Column("tool") == tool.rawValue)
                .filter(Self.activeStatusFilter)
                .fetchOne(db)
        }
    }

    /// Create a new session. If an active session exists for this pid+tool, end it first.
    @discardableResult
    public func startSession(
        tool: SessionTool, directory: String, pid: Int,
        conversationId: String? = nil,
        hostAppBundleId: String? = nil, hostAppName: String? = nil,
        transcriptPath: String? = nil
    ) throws -> Session {
        try dbPool.write { db in
            // End any existing active session for this pid+tool
            let existing = try Session
                .filter(Column("pid") == pid)
                .filter(Column("tool") == tool.rawValue)
                .filter(Self.activeStatusFilter)
                .fetchAll(db)

            let now = Date()
            for var session in existing {
                session.status = .completed
                session.updatedAt = now
                try session.update(db)
            }

            let session = Session(
                id: UUID().uuidString,
                conversationId: conversationId,
                tool: tool,
                directory: directory,
                lastAsk: nil,
                status: .idle,
                pid: pid,
                hostAppBundleId: hostAppBundleId,
                hostAppName: hostAppName,
                windowId: nil,
                transcriptPath: transcriptPath,
                startedAt: now,
                updatedAt: now
            )
            try session.insert(db)
            return session
        }
    }

    /// Update the active session for a pid+tool. Creates one if none exists (idempotent).
    @discardableResult
    public func updateSession(
        pid: Int, tool: SessionTool,
        ask: String? = nil, status: SessionStatus? = nil,
        transcriptPath: String? = nil,
        conversationId: String? = nil, directory: String? = nil
    ) throws -> Session {
        try dbPool.write { db in
            let now = Date()

            if var session = try Session
                .filter(Column("pid") == pid)
                .filter(Column("tool") == tool.rawValue)
                .filter(Self.activeStatusFilter)
                .fetchOne(db)
            {
                if let ask {
                    let truncated = String(ask.prefix(500))
                    session.lastAsk = truncated
                }
                if let status {
                    // Only transition to .waiting from .working to avoid race
                    // between Stop (→idle) and Notification (→waiting) hooks.
                    let skip = status == .waiting && session.status != .working
                    if !skip {
                        session.status = status
                    }
                }
                if let transcriptPath {
                    session.transcriptPath = transcriptPath
                }
                if let conversationId {
                    session.conversationId = conversationId
                }
                if let directory {
                    session.directory = directory
                }
                session.updatedAt = now
                try session.update(db)
                return session
            }

            // No active session — create one
            let session = Session(
                id: UUID().uuidString,
                conversationId: conversationId,
                tool: tool,
                directory: directory ?? FileManager.default.currentDirectoryPath,
                lastAsk: ask.map { String($0.prefix(500)) },
                status: status ?? .idle,
                pid: pid,
                hostAppBundleId: nil,
                hostAppName: nil,
                windowId: nil,
                transcriptPath: transcriptPath,
                startedAt: now,
                updatedAt: now
            )
            try session.insert(db)
            return session
        }
    }

    /// End the active session for a pid+tool.
    public func endSession(pid: Int, tool: SessionTool, status: SessionStatus = .completed) throws {
        try dbPool.write { db in
            if var session = try Session
                .filter(Column("pid") == pid)
                .filter(Column("tool") == tool.rawValue)
                .filter(Self.activeStatusFilter)
                .fetchOne(db)
            {
                session.status = status
                session.updatedAt = Date()
                try session.update(db)
            }
        }
    }

    /// List sessions ordered by updated_at DESC.
    public func listSessions(
        limit: Int = 20, status: SessionStatus? = nil, tool: SessionTool? = nil
    ) throws -> [Session] {
        try dbPool.read { db in
            var query = Session.order(Column("updated_at").desc)
            if let status {
                query = query.filter(Column("status") == status.rawValue)
            }
            if let tool {
                query = query.filter(Column("tool") == tool.rawValue)
            }
            return try query.limit(limit).fetchAll(db)
        }
    }

    /// Fetch a single session by ID.
    public func getSession(id: String) throws -> Session? {
        try dbPool.read { db in
            try Session.fetchOne(db, key: id)
        }
    }

    /// Garbage collect: delete old completed sessions and mark stale ones.
    /// Returns (deleted, marked_stale) counts.
    @discardableResult
    public func gc(olderThan: TimeInterval = 30 * 24 * 3600, isProcessAlive: (Int) -> Bool = { pid in
        kill(Int32(pid), 0) == 0
    }) throws -> (deleted: Int, markedStale: Int) {
        try dbPool.write { db in
            let cutoff = Date().addingTimeInterval(-olderThan)

            // Delete old completed/canceled/stale sessions
            let deleted = try Session
                .filter(Column("status") == SessionStatus.completed.rawValue
                    || Column("status") == SessionStatus.canceled.rawValue
                    || Column("status") == SessionStatus.stale.rawValue)
                .filter(Column("updated_at") < cutoff)
                .deleteAll(db)

            // Mark stale: active sessions whose PID is dead
            let activeSessions = try Session
                .filter(Self.activeStatusFilter)
                .fetchAll(db)

            var markedStale = 0
            for var session in activeSessions {
                if let pid = session.pid, !isProcessAlive(pid) {
                    session.status = .stale
                    session.updatedAt = Date()
                    try session.update(db)
                    markedStale += 1
                }
            }

            return (deleted: deleted, markedStale: markedStale)
        }
    }
}
