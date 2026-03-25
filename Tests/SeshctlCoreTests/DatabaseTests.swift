import Foundation
import Testing

@testable import SeshctlCore

@Suite("Database")
struct DatabaseTests {
    @Test("Creates database and runs migrations")
    func createDatabase() throws {
        let db = try SeshctlDatabase.temporary()
        let sessions = try db.listSessions()
        #expect(sessions.isEmpty)
    }

    @Test("Start creates a session")
    func startSession() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp/test", pid: 1234)

        #expect(session.tool == .claude)
        #expect(session.directory == "/tmp/test")
        #expect(session.pid == 1234)
        #expect(session.status == .idle)
        #expect(!session.id.isEmpty)
    }

    @Test("Start with conversation ID")
    func startWithConversationId() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(
            tool: .claude, directory: "/tmp", pid: 1234,
            conversationId: "conv-abc"
        )
        #expect(session.conversationId == "conv-abc")
    }

    @Test("Start ends existing active session for same pid+tool")
    func startEndsExisting() throws {
        let db = try SeshctlDatabase.temporary()
        let first = try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1234)
        let second = try db.startSession(tool: .claude, directory: "/tmp/b", pid: 1234)

        #expect(first.id != second.id)

        // First should now be completed
        let firstFetched = try db.getSession(id: first.id)
        #expect(firstFetched?.status == .completed)

        // Second should be active
        let secondFetched = try db.getSession(id: second.id)
        #expect(secondFetched?.status == .idle)
    }

    @Test("Start does not end sessions for different pid")
    func startDifferentPid() throws {
        let db = try SeshctlDatabase.temporary()
        let first = try db.startSession(tool: .claude, directory: "/tmp", pid: 1111)
        _ = try db.startSession(tool: .claude, directory: "/tmp", pid: 2222)

        let firstFetched = try db.getSession(id: first.id)
        #expect(firstFetched?.status == .idle)
    }

    @Test("Start does not end sessions for different tool")
    func startDifferentTool() throws {
        let db = try SeshctlDatabase.temporary()
        let first = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        _ = try db.startSession(tool: .gemini, directory: "/tmp", pid: 1234)

        let firstFetched = try db.getSession(id: first.id)
        #expect(firstFetched?.status == .idle)
    }

    @Test("Update modifies active session")
    func updateSession() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let updated = try db.updateSession(
            pid: 1234, tool: .claude,
            ask: "hello world", status: .working
        )

        #expect(updated.lastAsk == "hello world")
        #expect(updated.status == .working)
    }

    @Test("Update truncates ask to 500 chars")
    func updateTruncatesAsk() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let longAsk = String(repeating: "x", count: 1000)
        let updated = try db.updateSession(pid: 1234, tool: .claude, ask: longAsk)

        #expect(updated.lastAsk?.count == 500)
    }

    @Test("Update creates session if none exists (idempotent)")
    func updateCreatesSession() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.updateSession(
            pid: 9999, tool: .gemini,
            ask: "hello", status: .working
        )

        #expect(session.tool == .gemini)
        #expect(session.pid == 9999)
        #expect(session.lastAsk == "hello")
        #expect(session.status == .working)
    }

    @Test("End sets session to completed")
    func endSession() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.endSession(pid: 1234, tool: .claude)

        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.status == .completed)
    }

    @Test("End with canceled status")
    func endCanceled() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.endSession(pid: 1234, tool: .claude, status: .canceled)

        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.status == .canceled)
    }

    @Test("End on already-ended session is a no-op")
    func endAlreadyEnded() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.endSession(pid: 1234, tool: .claude)
        // Should not throw
        try db.endSession(pid: 1234, tool: .claude)
    }

    @Test("List returns sessions ordered by updated_at DESC")
    func listOrder() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp/a", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp/b", pid: 2222)
        try db.startSession(tool: .codex, directory: "/tmp/c", pid: 3333)

        let sessions = try db.listSessions()
        #expect(sessions.count == 3)
        // Most recent first
        #expect(sessions[0].tool == .codex)
    }

    @Test("List filters by status")
    func listFilterStatus() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp", pid: 2222)
        try db.endSession(pid: 2222, tool: .gemini)

        let idle = try db.listSessions(status: .idle)
        #expect(idle.count == 1)
        #expect(idle[0].tool == .claude)

        let completed = try db.listSessions(status: .completed)
        #expect(completed.count == 1)
        #expect(completed[0].tool == .gemini)
    }

    @Test("List filters by tool")
    func listFilterTool() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1111)
        try db.startSession(tool: .gemini, directory: "/tmp", pid: 2222)

        let claudeOnly = try db.listSessions(tool: .claude)
        #expect(claudeOnly.count == 1)
        #expect(claudeOnly[0].tool == .claude)
    }

    @Test("List respects limit")
    func listLimit() throws {
        let db = try SeshctlDatabase.temporary()
        for i in 1...5 {
            try db.startSession(tool: .claude, directory: "/tmp", pid: i)
        }

        let sessions = try db.listSessions(limit: 3)
        #expect(sessions.count == 3)
    }

    @Test("Show returns session by ID")
    func showSession() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.id == session.id)
        #expect(fetched?.tool == .claude)
    }

    @Test("Show returns nil for unknown ID")
    func showUnknown() throws {
        let db = try SeshctlDatabase.temporary()
        let fetched = try db.getSession(id: "nonexistent")
        #expect(fetched == nil)
    }

    @Test("Multiple sessions can share a conversation ID")
    func conversationContinuity() throws {
        let db = try SeshctlDatabase.temporary()
        let first = try db.startSession(
            tool: .claude, directory: "/tmp", pid: 1111,
            conversationId: "conv-123"
        )
        try db.endSession(pid: 1111, tool: .claude)

        let second = try db.startSession(
            tool: .claude, directory: "/tmp", pid: 2222,
            conversationId: "conv-123"
        )

        #expect(first.conversationId == second.conversationId)
        #expect(first.id != second.id)
    }

    @Test("GC deletes old completed sessions")
    func gcDeletesOld() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.endSession(pid: 1234, tool: .claude)

        // Negative olderThan puts the cutoff in the future, so everything is "old"
        let (deleted, _) = try db.gc(olderThan: -1)
        #expect(deleted == 1)

        let sessions = try db.listSessions()
        #expect(sessions.isEmpty)
    }

    @Test("GC marks stale sessions when PID is dead")
    func gcMarksStale() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 99999)

        let (_, markedStale) = try db.gc(isProcessAlive: { _ in false })
        #expect(markedStale == 1)

        let sessions = try db.listSessions(status: .stale)
        #expect(sessions.count == 1)
    }

    @Test("GC does not mark stale if PID is alive")
    func gcDoesNotMarkAlive() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let (_, markedStale) = try db.gc(isProcessAlive: { _ in true })
        #expect(markedStale == 0)

        let sessions = try db.listSessions(status: .idle)
        #expect(sessions.count == 1)
    }

    @Test("Status transitions: idle → working → idle")
    func statusTransitions() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        var session = try db.updateSession(pid: 1234, tool: .claude, status: .working)
        #expect(session.status == .working)

        session = try db.updateSession(pid: 1234, tool: .claude, status: .idle)
        #expect(session.status == .idle)
    }

    @Test("Status transitions: working → waiting → working")
    func waitingStatusTransitions() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        var session = try db.updateSession(pid: 1234, tool: .claude, status: .working)
        #expect(session.status == .working)

        session = try db.updateSession(pid: 1234, tool: .claude, status: .waiting)
        #expect(session.status == .waiting)

        session = try db.updateSession(pid: 1234, tool: .claude, status: .working)
        #expect(session.status == .working)
    }

    @Test("Waiting counts as active")
    func waitingIsActive() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)
        let session = try db.updateSession(pid: 1234, tool: .claude, status: .waiting)

        #expect(session.isActive)
    }

    @Test("Waiting sessions appear in active session lookup")
    func waitingInActiveSessionLookup() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)
        try db.updateSession(pid: 1234, tool: .claude, status: .waiting)

        let found = try db.findActiveSession(pid: 1234, tool: .claude)
        #expect(found != nil)
        #expect(found?.status == .waiting)
    }

    @Test("Late Notification ignored when session is idle (Stop fired first)")
    func waitingIgnoredWhenIdle() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // Simulate: working → idle (Stop) → waiting (stale Notification)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)
        try db.updateSession(pid: 1234, tool: .claude, status: .idle)
        let session = try db.updateSession(pid: 1234, tool: .claude, status: .waiting)

        // Should remain idle — late Notification is stale
        #expect(session.status == .idle)
    }

    @Test("PreToolUse resumes working from waiting (ask answered)")
    func preToolUseResumesFromWaiting() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // Simulate: working → waiting (Notification) → working (PreToolUse)
        try db.updateSession(pid: 1234, tool: .claude, status: .working)
        try db.updateSession(pid: 1234, tool: .claude, status: .waiting)
        let session = try db.updateSession(pid: 1234, tool: .claude, status: .working)

        #expect(session.status == .working)
    }

    @Test("Full ask cycle: working → waiting → working → idle")
    func fullAskCycle() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // UserPromptSubmit → working
        var session = try db.updateSession(pid: 1234, tool: .claude, status: .working)
        #expect(session.status == .working)

        // Notification → waiting (Claude asks user)
        session = try db.updateSession(pid: 1234, tool: .claude, status: .waiting)
        #expect(session.status == .waiting)

        // PreToolUse → working (user answered, Claude resumes)
        session = try db.updateSession(pid: 1234, tool: .claude, status: .working)
        #expect(session.status == .working)

        // Stop → idle
        session = try db.updateSession(pid: 1234, tool: .claude, status: .idle)
        #expect(session.status == .idle)
    }

    @Test("Skip-git update preserves existing git fields")
    func skipGitPreservesFields() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        // Set git fields via normal update
        try db.updateSession(pid: 1234, tool: .claude, gitRepoName: "myrepo", gitBranch: "main")

        // Status-only update with nil git fields (simulates --skip-git)
        let session = try db.updateSession(pid: 1234, tool: .claude, status: .working)

        #expect(session.gitRepoName == "myrepo")
        #expect(session.gitBranch == "main")
    }

    @Test("Waiting transition ignored from completed session")
    func waitingIgnoredWhenCompleted() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        try db.endSession(pid: 1234, tool: .claude)

        // Verify the session is completed
        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.status == .completed)

        // A late Notification creates a new session (no active one to update)
        let created = try db.updateSession(pid: 1234, tool: .claude, status: .waiting)
        #expect(created.id != session.id)
        #expect(created.status == .waiting)

        // Original session unchanged
        let original = try db.getSession(id: session.id)
        #expect(original?.status == .completed)
    }

    @Test("findActiveSession returns the right session")
    func findActiveSession() throws {
        let db = try SeshctlDatabase.temporary()
        let created = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let found = try db.findActiveSession(pid: 1234, tool: .claude)
        #expect(found?.id == created.id)

        let notFound = try db.findActiveSession(pid: 1234, tool: .gemini)
        #expect(notFound == nil)
    }

    // MARK: - Unread (markSessionRead) Tests

    @Test("New sessions start as read")
    func newSessionStartsAsRead() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)
        #expect(session.lastReadAt != nil)
        #expect(session.lastReadAt == session.updatedAt)
    }

    @Test("markSessionRead sets last_read_at")
    func markSessionRead() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        try db.markSessionRead(id: session.id)

        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.lastReadAt != nil)
    }

    // MARK: - Git Context Tests

    @Test("Start stores git context")
    func startStoresGitContext() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(
            tool: .claude, directory: "/tmp/test", pid: 1234,
            gitRepoName: "seshctl", gitBranch: "main"
        )

        #expect(session.gitRepoName == "seshctl")
        #expect(session.gitBranch == "main")

        let fetched = try db.getSession(id: session.id)
        #expect(fetched?.gitRepoName == "seshctl")
        #expect(fetched?.gitBranch == "main")
    }

    @Test("Update stores git context")
    func updateStoresGitContext() throws {
        let db = try SeshctlDatabase.temporary()
        try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        let updated = try db.updateSession(
            pid: 1234, tool: .claude,
            gitRepoName: "seshctl", gitBranch: "feat-auth"
        )

        #expect(updated.gitRepoName == "seshctl")
        #expect(updated.gitBranch == "feat-auth")

        let fetched = try db.getSession(id: updated.id)
        #expect(fetched?.gitRepoName == "seshctl")
        #expect(fetched?.gitBranch == "feat-auth")
    }

    @Test("Start with nil git context")
    func startWithNilGitContext() throws {
        let db = try SeshctlDatabase.temporary()
        let session = try db.startSession(tool: .claude, directory: "/tmp", pid: 1234)

        #expect(session.gitRepoName == nil)
        #expect(session.gitBranch == nil)
    }
}
