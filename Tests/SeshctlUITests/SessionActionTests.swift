import AppKit
import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

private func makeSession(
    id: String = UUID().uuidString,
    tool: SessionTool = .claude,
    conversationId: String? = "abc-123",
    directory: String = "/tmp",
    status: SessionStatus = .idle,
    pid: Int? = 12345,
    hostAppBundleId: String? = nil,
    launchArgs: String? = nil
) -> Session {
    Session(
        id: id,
        conversationId: conversationId,
        tool: tool,
        directory: directory,
        lastAsk: nil,
        lastReply: nil,
        status: status,
        pid: pid,
        hostAppBundleId: hostAppBundleId,
        hostAppName: nil,
        windowId: nil,
        transcriptPath: nil,
        gitRepoName: nil,
        gitBranch: nil,
        launchArgs: launchArgs,
        startedAt: Date(),
        updatedAt: Date(),
        lastReadAt: nil
    )
}

private func makeCallbacks() -> (
    markRead: (Session) -> Void,
    rememberFocused: (Session) -> Void,
    dismiss: () -> Void,
    markedRead: () -> [String],
    remembered: () -> [String],
    dismissed: () -> Int
) {
    var markedReadIds: [String] = []
    var rememberedIds: [String] = []
    var dismissCount = 0
    return (
        markRead: { markedReadIds.append($0.id) },
        rememberFocused: { rememberedIds.append($0.id) },
        dismiss: { dismissCount += 1 },
        markedRead: { markedReadIds },
        remembered: { rememberedIds },
        dismissed: { dismissCount }
    )
}

@Suite("SessionAction", .serialized)
struct SessionActionTests {

    @Test("Active session marks read, remembers, and dismisses")
    func activeSessionMarksReadRemembersDismisses() {
        let session = makeSession(status: .idle, pid: 12345)
        let env = MockSystemEnvironment()
        env.guiApps = [12345: "com.apple.Terminal"]
        env.ttys = [12345: "/dev/ttys042"]
        let cb = makeCallbacks()
        SessionAction.execute(
            target: .activeSession(session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.markedRead() == [session.id])
        #expect(cb.remembered() == [session.id])
        #expect(cb.dismissed() == 1)
    }

    @Test("Inactive session with conversationId resumes and dismisses")
    func inactiveSessionWithConversationIdResumes() {
        let session = makeSession(
            conversationId: "abc-123",
            directory: "/tmp",
            status: .completed,
            hostAppBundleId: "com.apple.Terminal"
        )
        let env = MockSystemEnvironment()
        env.runningApps = ["com.apple.Terminal"]

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .inactiveSession(session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        #expect(cb.markedRead() == [session.id])
        #expect(env.shellCommands.contains { $0.1.contains("-b") && $0.1.contains("com.apple.Terminal") })
    }

    @Test("Inactive session without conversationId falls back to focus")
    func inactiveSessionWithoutConversationIdFallsToFocus() {
        let session = makeSession(
            conversationId: nil,
            status: .completed,
            pid: 12345
        )
        let env = MockSystemEnvironment()
        env.guiApps = [12345: "com.apple.Terminal"]
        env.ttys = [12345: "/dev/ttys042"]

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .inactiveSession(session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        #expect(env.shellCommands.contains { $0.1.contains("-b") && $0.1.contains("com.apple.Terminal") })
    }

    @Test("Recall result with active session focuses it")
    func recallResultWithActiveSessionFocuses() {
        let session = makeSession(status: .idle, pid: 12345)
        let env = MockSystemEnvironment()
        env.guiApps = [12345: "com.apple.Terminal"]
        env.ttys = [12345: "/dev/ttys042"]

        let result = RecallResult(
            agent: "claude",
            role: "assistant",
            sessionId: "abc-123",
            project: "/tmp",
            timestamp: Date().timeIntervalSince1970,
            score: 0.95,
            resumeCmd: "claude --resume abc-123",
            text: "some text"
        )

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .recallResult(result, matchedSession: session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.markedRead() == [session.id])
        #expect(cb.remembered() == [session.id])
        #expect(cb.dismissed() == 1)
    }

    @Test("Recall result resumes using resumeCmd and dismisses")
    func recallResultResumes() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.apple.Terminal"]

        let result = RecallResult(
            agent: "claude",
            role: "assistant",
            sessionId: "abc-123",
            project: "/tmp",
            timestamp: Date().timeIntervalSince1970,
            score: 0.95,
            resumeCmd: "claude --resume abc-123",
            text: "some text"
        )

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .recallResult(result),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        #expect(env.shellCommands.contains { $0.1.contains("com.apple.Terminal") })
    }

    @Test("Recall result with inactive matched session resumes using session host app")
    func recallResultWithInactiveMatchedSessionUsesHostApp() {
        let session = makeSession(
            conversationId: "abc-123",
            status: .completed,
            pid: nil,
            hostAppBundleId: "com.todesktop.230313mzl4w4u92"
        )
        let env = MockSystemEnvironment()
        // Set a different frontmost app to prove we use the session's host app, not frontmost
        env.frontmostApp = "com.apple.Terminal"
        env.runningApps = ["com.apple.Terminal", "com.todesktop.230313mzl4w4u92"]

        let result = RecallResult(
            agent: "claude",
            role: "assistant",
            sessionId: "abc-123",
            project: "/tmp",
            timestamp: Date().timeIntervalSince1970,
            score: 0.95,
            resumeCmd: "claude --resume abc-123",
            text: "some text"
        )

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .recallResult(result, matchedSession: session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        // Verify resume dispatched to the session's host app, not the frontmost terminal
        #expect(env.shellCommands.contains { $0.1.contains("com.todesktop.230313mzl4w4u92") })
        #expect(!env.shellCommands.contains { $0.1.contains("com.apple.Terminal") })
    }

    @Test("Recall result copies to clipboard when no terminal available")
    func recallResultFallsBackToClipboard() {
        let env = MockSystemEnvironment()
        // Non-existent project directory — resume will fail

        let result = RecallResult(
            agent: "claude",
            role: "assistant",
            sessionId: "abc-123",
            project: "/nonexistent/path",
            timestamp: Date().timeIntervalSince1970,
            score: 0.95,
            resumeCmd: "claude --resume abc-123",
            text: "some text"
        )

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .recallResult(result),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "cd /nonexistent/path && claude --resume abc-123")
    }

    @Test("Recall result passes resumeCmd through directly to resume")
    func recallResultPassesResumeCmdDirectly() {
        // resumeCmd is now a bare command (no cd prefix) — verify it's passed through as-is
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp",
            app: .terminal
        )
        #expect(script?.contains("cd /tmp && claude --resume abc-123") == true)
    }

    @Test("Resume failure copies command to clipboard")
    func resumeFailureCopiesCommandToClipboard() {
        let session = makeSession(
            conversationId: "abc-123",
            directory: "/tmp",
            status: .completed,
            pid: nil,
            hostAppBundleId: nil
        )
        let env = MockSystemEnvironment()

        let cb = makeCallbacks()
        SessionAction.execute(
            target: .inactiveSession(session),
            markRead: cb.markRead,
            rememberFocused: cb.rememberFocused,
            dismiss: cb.dismiss,
            environment: env
        )

        #expect(cb.dismissed() == 1)
        #expect(NSPasteboard.general.string(forType: .string) == "claude --resume abc-123")
    }
}
