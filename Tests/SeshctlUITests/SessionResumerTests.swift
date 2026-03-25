import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

@Suite("SessionResumer")
struct SessionResumerTests {

    // MARK: - Helpers

    private func makeSession(
        tool: SessionTool = .claude,
        directory: String = "/tmp/project",
        conversationId: String? = "abc-123",
        launchArgs: String? = nil,
        hostAppBundleId: String? = nil
    ) -> Session {
        Session(
            id: UUID().uuidString,
            conversationId: conversationId,
            tool: tool,
            directory: directory,
            lastAsk: nil,
            lastReply: nil,
            status: .idle,
            pid: 12345,
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

    // MARK: - buildResumeCommand Tests

    @Suite("buildResumeCommand")
    struct BuildResumeCommandTests {

        private func makeSession(
            tool: SessionTool = .claude,
            conversationId: String? = "abc-123",
            launchArgs: String? = nil
        ) -> Session {
            Session(
                id: UUID().uuidString,
                conversationId: conversationId,
                tool: tool,
                directory: "/tmp/project",
                lastAsk: nil,
                lastReply: nil,
                status: .idle,
                pid: 12345,
                hostAppBundleId: nil,
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

        @Test("Claude with launchArgs and conversationId")
        func claudeWithArgs() {
            let session = makeSession(
                tool: .claude,
                conversationId: "abc-123",
                launchArgs: "--dangerously-skip-permissions"
            )
            let command = SessionResumer.buildResumeCommand(session: session)
            #expect(command == "claude --dangerously-skip-permissions --resume abc-123")
        }

        @Test("Codex with launchArgs and conversationId")
        func codexWithArgs() {
            let session = makeSession(
                tool: .codex,
                conversationId: "def-456",
                launchArgs: "--full-auto"
            )
            let command = SessionResumer.buildResumeCommand(session: session)
            #expect(command == "codex --full-auto --resume def-456")
        }

        @Test("Gemini with no launchArgs")
        func geminiNoArgs() {
            let session = makeSession(
                tool: .gemini,
                conversationId: "ghi-789",
                launchArgs: nil
            )
            let command = SessionResumer.buildResumeCommand(session: session)
            #expect(command == "gemini --resume ghi-789")
        }

        @Test("Empty string launchArgs produces no extra space")
        func emptyLaunchArgs() {
            let session = makeSession(
                tool: .claude,
                conversationId: "abc-123",
                launchArgs: ""
            )
            let command = SessionResumer.buildResumeCommand(session: session)
            #expect(command == "claude --resume abc-123")
        }

        @Test("Nil conversationId returns nil")
        func nilConversationId() {
            let session = makeSession(
                tool: .claude,
                conversationId: nil
            )
            let command = SessionResumer.buildResumeCommand(session: session)
            #expect(command == nil)
        }
    }

    // MARK: - buildResumeScript Tests

    @Suite("buildResumeScript")
    struct BuildResumeScriptTests {

        @Test("Terminal.app script contains do script and escaped command")
        func terminalScript() {
            let script = SessionResumer.buildResumeScript(
                command: "claude --resume abc-123",
                directory: "/tmp/project",
                bundleId: "com.apple.Terminal"
            )

            #expect(script != nil)
            #expect(script!.contains("do script"))
            #expect(script!.contains("claude --resume abc-123"))
        }

        @Test("iTerm2 script contains write text and escaped command")
        func itermScript() {
            let script = SessionResumer.buildResumeScript(
                command: "claude --resume abc-123",
                directory: "/tmp/project",
                bundleId: "com.googlecode.iterm2"
            )

            #expect(script != nil)
            #expect(script!.contains("write text"))
            #expect(script!.contains("claude --resume abc-123"))
        }

        @Test("Unknown bundle ID returns nil")
        func unknownBundleId() {
            let script = SessionResumer.buildResumeScript(
                command: "claude --resume abc-123",
                directory: "/tmp/project",
                bundleId: "com.example.UnknownApp"
            )

            #expect(script == nil)
        }

        @Test("Special characters in command are properly escaped")
        func specialCharactersEscaped() {
            let command = "claude --resume \"conv-123\" --flag 'value\\path'"
            let script = SessionResumer.buildResumeScript(
                command: command,
                directory: "/tmp/project",
                bundleId: "com.apple.Terminal"
            )

            #expect(script != nil)
            // Quotes should be escaped for AppleScript
            #expect(script!.contains("\\\""))
            // Backslashes should be escaped for AppleScript
            #expect(script!.contains("\\\\"))
        }
    }

    // MARK: - Routing Tests

    @Suite("resume routing")
    struct ResumeRoutingTests {

        @Test("Returns false when bundleId is nil")
        func nilBundleIdReturnsFalse() {
            let result = SessionResumer.resume(
                command: "claude --resume abc-123",
                directory: "/tmp",
                bundleId: nil
            )
            #expect(result == false)
        }

        @Test("Returns false when directory does not exist")
        func nonexistentDirectoryReturnsFalse() {
            let result = SessionResumer.resume(
                command: "claude --resume abc-123",
                directory: "/nonexistent/path/that/does/not/exist",
                bundleId: "com.apple.Terminal"
            )
            #expect(result == false)
        }
    }
}
