import AppKit
import ArgumentParser
import Foundation
import SeshctlCore

@main
struct SeshctlCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seshctl-cli",
        abstract: "Track and manage active LLM CLI sessions.",
        subcommands: [Start.self, Update.self, End.self, List.self, Show.self, GC.self, Install.self, Uninstall.self]
    )
}

// MARK: - Helpers

func openDatabase() throws -> SeshctlDatabase {
    let path = NSString(
        string: "~/.local/share/seshctl/seshctl.db"
    ).expandingTildeInPath
    return try SeshctlDatabase(path: path)
}

extension SessionTool: ExpressibleByArgument {}
extension SessionStatus: ExpressibleByArgument {}

// MARK: - Start

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a new session."
    )

    @Option(help: "Tool name (claude, gemini, codex).")
    var tool: SessionTool

    @Option(help: "Working directory.")
    var dir: String

    @Option(help: "CLI process PID.")
    var pid: Int

    @Option(name: .long, help: "Conversation/session ID from the CLI.")
    var conversationId: String?

    @Option(name: .long, help: "Host app bundle ID (e.g., com.microsoft.VSCode).")
    var hostAppBundleId: String?

    @Option(name: .long, help: "Host app name (e.g., Code).")
    var hostAppName: String?

    @Option(name: .long, help: "Transcript file path.")
    var transcriptPath: String?

    func run() throws {
        let db = try openDatabase()

        // Auto-detect host app from PID if not provided
        var bundleId = hostAppBundleId
        var appName = hostAppName
        if bundleId == nil {
            let detected = detectHostApp(pid: Int32(pid))
            bundleId = detected.bundleId
            appName = detected.name
        }

        // Detect git context
        let gitContext = GitContext.detect(directory: dir)

        let session = try db.startSession(
            tool: tool, directory: dir, pid: pid,
            conversationId: conversationId,
            hostAppBundleId: bundleId, hostAppName: appName,
            transcriptPath: transcriptPath,
            gitRepoName: gitContext.repoName, gitBranch: gitContext.branch
        )
        print(session.id)
    }

    private func detectHostApp(pid: pid_t) -> (bundleId: String?, name: String?) {
        var currentPid = pid
        for _ in 0..<10 {
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.stride
            let result = proc_pidinfo(currentPid, PROC_PIDTBSDINFO, 0, &info, Int32(size))

            // Check if this PID has a GUI app via NSWorkspace
            // We can't use NSRunningApplication in a CLI, so check via bundle path
            let parentPid: pid_t = result == size ? pid_t(info.pbi_ppid) : 0

            // Try to find app by checking running apps
            for app in NSWorkspace.shared.runningApplications {
                if app.processIdentifier == currentPid && app.activationPolicy == .regular {
                    return (app.bundleIdentifier, app.localizedName)
                }
            }

            if parentPid <= 1 || parentPid == currentPid { break }
            currentPid = parentPid
        }
        return (nil, nil)
    }
}

// MARK: - Update

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update the active session for a pid+tool."
    )

    @Option(help: "CLI process PID.")
    var pid: Int

    @Option(help: "Tool name (claude, gemini, codex).")
    var tool: SessionTool

    @Option(help: "User's message/prompt.")
    var ask: String?

    @Option(help: "Assistant's last response text.")
    var reply: String?

    @Option(help: "New status (idle, working, waiting).")
    var status: SessionStatus?

    @Option(name: .long, help: "Transcript file path.")
    var transcriptPath: String?

    @Option(name: .long, help: "Conversation/session ID.")
    var conversationId: String?

    @Option(name: .long, help: "Working directory.")
    var dir: String?

    @Flag(name: .long, help: "Skip git context detection (faster for status-only updates).")
    var skipGit = false

    func run() throws {
        let db = try openDatabase()

        var gitRepoName: String?
        var gitBranch: String?
        if !skipGit, let session = try db.findActiveSession(pid: pid, tool: tool) {
            let gitContext = GitContext.detect(directory: dir ?? session.directory)
            gitRepoName = gitContext.repoName
            gitBranch = gitContext.branch
        }

        try db.updateSession(pid: pid, tool: tool, ask: ask, reply: reply, status: status, transcriptPath: transcriptPath, conversationId: conversationId, directory: dir, gitRepoName: gitRepoName, gitBranch: gitBranch)
    }
}

// MARK: - End

struct End: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "End the active session for a pid+tool."
    )

    @Option(help: "CLI process PID.")
    var pid: Int

    @Option(help: "Tool name (claude, gemini, codex).")
    var tool: SessionTool

    @Option(help: "Final status (completed, canceled).")
    var status: SessionStatus?

    func run() throws {
        let db = try openDatabase()
        try db.endSession(pid: pid, tool: tool, status: status ?? .completed)
    }
}

// MARK: - List

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List sessions ordered by most recently updated."
    )

    @Option(help: "Max number of sessions to show.")
    var limit: Int = 20

    @Option(help: "Filter by status.")
    var status: SessionStatus?

    @Option(help: "Filter by tool.")
    var tool: SessionTool?

    func run() throws {
        let db = try openDatabase()
        let sessions = try db.listSessions(limit: limit, status: status, tool: tool)

        if sessions.isEmpty {
            print("No sessions found.")
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        for session in sessions {
            let age = formatter.localizedString(for: session.updatedAt, relativeTo: Date())
            let dir = session.displayName
            let ask = session.lastAsk.map { " \"\(String($0.prefix(60)))\"" } ?? ""
            print(
                "\(session.id.prefix(8))  \(session.tool.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) \(session.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(dir.padding(toLength: 40, withPad: " ", startingAt: 0)) \(age)\(ask)"
            )
        }
    }
}

// MARK: - Show

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show full details for a session."
    )

    @Argument(help: "Session ID (full UUID or prefix).")
    var id: String

    func run() throws {
        let db = try openDatabase()

        guard let session = try db.getSession(id: id) else {
            throw ValidationError("Session not found: \(id)")
        }

        let iso = ISO8601DateFormatter()
        print("ID:              \(session.id)")
        print("Tool:            \(session.tool.rawValue)")
        print("Status:          \(session.status.rawValue)")
        print("Directory:       \(session.directory)")
        if let repo = session.gitRepoName {
            print("Git Repo:        \(repo)")
        }
        if let branch = session.gitBranch {
            print("Git Branch:      \(branch)")
        }
        if let cid = session.conversationId {
            print("Conversation ID: \(cid)")
        }
        if let pid = session.pid {
            print("PID:             \(pid)")
        }
        if let ask = session.lastAsk {
            print("Last Ask:        \(ask)")
        }
        if let reply = session.lastReply {
            print("Last Reply:      \(reply)")
        }
        print("Started:         \(iso.string(from: session.startedAt))")
        print("Updated:         \(iso.string(from: session.updatedAt))")
    }
}

// MARK: - GC

struct GC: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gc",
        abstract: "Garbage collect old sessions and reap stale ones."
    )

    @Option(help: "Delete completed sessions older than this (e.g., 30d, 7d).")
    var olderThan: String = "30d"

    func run() throws {
        let db = try openDatabase()

        guard let seconds = parseDuration(olderThan) else {
            throw ValidationError("Invalid duration: \(olderThan). Use format like 30d, 7d, 24h.")
        }

        let (deleted, markedStale) = try db.gc(olderThan: seconds)
        print("Deleted \(deleted) old sessions, marked \(markedStale) as stale.")
    }

    private func parseDuration(_ s: String) -> TimeInterval? {
        let pattern = /^(\d+)([dhm])$/
        guard let match = s.wholeMatch(of: pattern) else { return nil }
        let value = Double(match.1)!
        switch match.2 {
        case "d": return value * 86400
        case "h": return value * 3600
        case "m": return value * 60
        default: return nil
        }
    }
}
