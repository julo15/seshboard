import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

// MARK: - Mock System Environment

final class MockSystemEnvironment: SystemEnvironment, @unchecked Sendable {
    var parentPids: [pid_t: pid_t] = [:]
    var guiApps: [pid_t: String] = [:]
    var appNames: [pid_t: String] = [:]
    var ttys: [Int: String] = [:]
    var frontmostApp: String? = nil
    var runningApps: [String] = []
    var activatedApps: [String] = []
    var executedScripts: [String] = []
    var shellCommands: [(String, [String])] = []
    var openedURLs: [URL] = []

    func parentPid(of pid: pid_t) -> pid_t { parentPids[pid] ?? 0 }
    func guiAppBundleId(for pid: pid_t) -> String? { guiApps[pid] }
    func guiAppName(for pid: pid_t) -> String? { appNames[pid] }
    func tty(for pid: Int) -> String? { ttys[pid] }
    func frontmostAppBundleId() -> String? { frontmostApp }
    func runningAppBundleIds() -> [String] { runningApps }
    func activateApp(bundleId: String) { activatedApps.append(bundleId) }
    func runAppleScript(_ script: String) { executedScripts.append(script) }
    func runShellCommand(_ path: String, args: [String]) { shellCommands.append((path, args)) }
    func openURL(_ url: URL) { openedURLs.append(url) }
}

// MARK: - App Discovery Tests

@Suite("TerminalController - App Discovery")
struct AppDiscoveryTests {
    @Test("Walks process tree to find VS Code")
    func findsVSCodeViaTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300]
        env.guiApps = [300: "com.microsoft.VSCode"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.microsoft.VSCode")
    }

    @Test("Walks process tree to find Terminal.app")
    func findsTerminalViaTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300]
        env.guiApps = [300: "com.apple.Terminal"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Falls back to running terminal app when tree walk fails")
    func fallsBackToRunningApp() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300, 300: 0]
        env.runningApps = ["com.apple.Terminal"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Fallback prefers Terminal over iTerm if both running")
    func fallbackPrefersTerminal() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 0]
        env.runningApps = ["com.apple.Terminal", "com.googlecode.iterm2"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Returns nil when no terminal app found and tree walk fails")
    func returnsNilWhenNoApp() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 0]
        env.runningApps = ["com.spotify.client"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == nil)
    }

    @Test("Handles deep process tree")
    func deepProcessTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 101, 101: 102, 102: 103, 103: 104]
        env.guiApps = [104: "com.apple.Terminal"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Stops at max depth to avoid infinite loops")
    func maxDepthSafety() {
        let env = MockSystemEnvironment()
        for i in 100..<115 {
            env.parentPids[pid_t(i)] = pid_t(i + 1)
        }
        env.guiApps = [115: "com.apple.Terminal"]
        env.runningApps = []

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == nil)
    }

    @Test("PID that is itself a GUI app")
    func pidIsGuiApp() {
        let env = MockSystemEnvironment()
        env.guiApps = [100: "com.apple.Terminal"]

        let bundleId = TerminalController.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }
}

// MARK: - Script Generation Tests

@Suite("TerminalController - Script Generation")
struct ScriptGenerationTests {
    @Test("Terminal.app script matches by TTY")
    func terminalScript() {
        let script = TerminalController.buildFocusScript(
            app: .terminal,
            appName: "Terminal",
            tty: "/dev/ttys042",
            directory: "/Users/me/projects/cool-app"
        )

        #expect(script != nil)
        #expect(script!.contains("tell application \"Terminal\""))
        #expect(script!.contains("tty of t is \"/dev/ttys042\""))
        #expect(script!.contains("set selected of t to true"))
        #expect(script!.contains("set index of w to 1"))
    }

    @Test("Terminal.app returns nil without TTY")
    func terminalScriptNoTty() {
        let script = TerminalController.buildFocusScript(
            app: .terminal,
            appName: "Terminal",
            tty: nil,
            directory: "/Users/me/project"
        )
        #expect(script == nil)
    }

    @Test("iTerm2 script matches by TTY")
    func itermScript() {
        let script = TerminalController.buildFocusScript(
            app: .iterm2,
            appName: "iTerm2",
            tty: "/dev/ttys007",
            directory: "/Users/me/project"
        )

        #expect(script != nil)
        #expect(script!.contains("tell application \"iTerm2\""))
        #expect(script!.contains("tty of s is \"/dev/ttys007\""))
        #expect(script!.contains("select s"))
        #expect(script!.contains("select w"))
    }

    @Test("iTerm2 returns nil without TTY")
    func itermScriptNoTty() {
        let script = TerminalController.buildFocusScript(
            app: .iterm2,
            appName: "iTerm2",
            tty: nil,
            directory: "/Users/me/project"
        )
        #expect(script == nil)
    }

    @Test("Ghostty script matches by working directory with selected-tab priority")
    func ghosttyScript() {
        let script = TerminalController.buildFocusScript(
            app: .ghostty,
            appName: "Ghostty",
            tty: "/dev/ttys042",
            directory: "/Users/me/projects/cool-app"
        )

        #expect(script != nil)
        #expect(script!.contains("tell application \"Ghostty\""))
        #expect(script!.contains("working directory of trm is \"/Users/me/projects/cool-app\""))
        // Should check front window's selected tab first, then fall back to full scan
        let selectedTabCheck = script!.range(of: "selected tab of front window")!
        let fullScan = script!.range(of: "select tab t")!
        #expect(selectedTabCheck.lowerBound < fullScan.lowerBound)
    }

    @Test("Ghostty script works without TTY (uses directory instead)")
    func ghosttyScriptNoTty() {
        let script = TerminalController.buildFocusScript(
            app: .ghostty,
            appName: "Ghostty",
            tty: nil,
            directory: "/Users/me/project"
        )

        #expect(script != nil)
        #expect(script!.contains("working directory of trm is \"/Users/me/project\""))
    }

    @Test("Ghostty script tries terminal ID first, then falls back to directory")
    func ghosttyScriptWithTerminalId() {
        let script = TerminalController.buildFocusScript(
            app: .ghostty,
            appName: "Ghostty",
            tty: "/dev/ttys042",
            directory: "/Users/me/projects/cool-app",
            windowId: "F63A60A0-F28D-4FDC-8666-5844F57BDC1D"
        )

        #expect(script != nil)
        #expect(script!.contains("tell application \"Ghostty\""))
        #expect(script!.contains("id of trm is \"F63A60A0-F28D-4FDC-8666-5844F57BDC1D\""))
        // Must also include directory fallback (ID may be stale after resume)
        #expect(script!.contains("working directory"))
        // ID match should come before directory fallback
        let idMatch = script!.range(of: "id of trm is")!
        let dirMatch = script!.range(of: "working directory")!
        #expect(idMatch.lowerBound < dirMatch.lowerBound)
    }

    @Test("Warp focus script uses TTY-based tab position via pgrep/ps")
    func warpScript() {
        let script = TerminalController.buildFocusScript(
            app: .warp,
            appName: "Warp",
            tty: "/dev/ttys007",
            directory: "/Users/me/projects/cool-app"
        )

        #expect(script != nil)
        #expect(script!.contains("ttys007"))
        #expect(script!.contains("pgrep"))
        #expect(script!.contains("keystroke"))
        #expect(script!.contains("using command down"))
        #expect(script!.contains("\"System Events\""))
        #expect(script!.contains("quoted form of ttyName"))
    }

    @Test("Warp focus script falls back to window name matching when no TTY")
    func warpScriptFallback() {
        let script = TerminalController.buildFocusScript(
            app: .warp,
            appName: "Warp",
            tty: nil,
            directory: "/Users/me/projects/cool-app"
        )

        #expect(script != nil)
        #expect(script!.contains("name of w contains \"cool-app\""))
        #expect(!script!.contains("pgrep"))
    }

    @Test("VS Code falls through to generic script in buildFocusScript (handled separately via focusVSCode)")
    func vscodeFallsToGeneric() {
        let script = TerminalController.buildFocusScript(
            app: .vscode,
            appName: "Code",
            tty: "/dev/ttys001",
            directory: "/Users/me/projects/seshctl"
        )

        // VS Code is handled separately by focusVSCode(), so buildFocusScript
        // returns the generic System Events script as fallback.
        #expect(script != nil)
        #expect(script!.contains("tell process \"Code\""))
        #expect(script!.contains("seshctl"))
    }

    @Test("Unknown app uses generic System Events script")
    func unknownAppScript() {
        let script = TerminalController.buildFocusScript(
            app: nil,
            appName: "SomeTerminal",
            tty: nil,
            directory: "/Users/me/project"
        )

        #expect(script != nil)
        #expect(script!.contains("tell process \"SomeTerminal\""))
        #expect(script!.contains("name of w contains \"project\""))
    }

    @Test("Directory name is extracted from full path (generic app)")
    func directoryNameExtraction() {
        let script = TerminalController.buildFocusScript(
            app: nil,
            appName: "SomeApp",
            tty: nil,
            directory: "/Users/me/deeply/nested/my-project"
        )

        #expect(script != nil)
        #expect(script!.contains("name of w contains \"my-project\""))
    }

    @Test("Special characters in directory name are escaped (generic app)")
    func specialCharsEscaped() {
        let script = TerminalController.buildFocusScript(
            app: nil,
            appName: "SomeApp",
            tty: nil,
            directory: "/Users/me/project with \"quotes\""
        )

        #expect(script != nil)
        #expect(script!.contains("project with \\\"quotes\\\""))
    }

    @Test("Special characters in TTY are escaped")
    func ttyEscaped() {
        // TTYs shouldn't have special chars, but verify escaping works
        let script = TerminalController.buildFocusScript(
            app: .terminal,
            appName: "Terminal",
            tty: "/dev/ttys000",
            directory: "/tmp"
        )

        #expect(script != nil)
        #expect(script!.contains("/dev/ttys000"))
    }
}

// MARK: - AppleScript Escaping Tests

@Suite("TerminalController - Escaping")
struct EscapingTests {
    @Test("Escapes backslashes")
    func escapesBackslashes() {
        #expect(TerminalController.escapeForAppleScript("a\\b") == "a\\\\b")
    }

    @Test("Escapes double quotes")
    func escapesQuotes() {
        #expect(TerminalController.escapeForAppleScript("say \"hi\"") == "say \\\"hi\\\"")
    }

    @Test("Leaves normal strings unchanged")
    func normalStrings() {
        #expect(TerminalController.escapeForAppleScript("hello world") == "hello world")
    }

    @Test("Handles empty string")
    func emptyString() {
        #expect(TerminalController.escapeForAppleScript("") == "")
    }

    @Test("Handles mixed special characters")
    func mixedSpecials() {
        let result = TerminalController.escapeForAppleScript("path\\to\\\"file\"")
        #expect(result == "path\\\\to\\\\\\\"file\\\"")
    }

    @Test("Strips newlines to prevent AppleScript injection")
    func stripsNewlines() {
        let malicious = "test\nend tell\ntell application \"Evil\""
        let result = TerminalController.escapeForAppleScript(malicious)
        // Newlines stripped — injection can't break out of string literal
        #expect(!result.contains("\n"))
        // Quotes are escaped — can't close the string literal
        #expect(!result.contains("\"Evil\""))
        #expect(result.contains("\\\"Evil\\\""))
    }

    @Test("Strips carriage returns")
    func stripsCarriageReturns() {
        let result = TerminalController.escapeForAppleScript("line1\r\nline2")
        #expect(!result.contains("\r"))
        #expect(!result.contains("\n"))
    }

    @Test("Replaces tabs with spaces")
    func replacesTabsWithSpaces() {
        let result = TerminalController.escapeForAppleScript("col1\tcol2")
        #expect(result == "col1 col2")
    }

    @Test("Strips null bytes and other control characters")
    func stripsControlChars() {
        let result = TerminalController.escapeForAppleScript("ab\0cd\u{07}ef")
        #expect(result == "abcdef")
    }

    @Test("Preserves unicode and emoji in directory names")
    func preservesUnicode() {
        let result = TerminalController.escapeForAppleScript("projet-été-🚀")
        #expect(result == "projet-été-🚀")
    }
}

// MARK: - Focus Routing Tests

@Suite("TerminalController - Focus Routing", .serialized)
struct FocusRoutingTests {
    @Test("Terminal.app focus uses open -b then AppleScript")
    func terminalRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [100: "com.apple.Terminal"]
        env.ttys = [100: "/dev/ttys001"]

        TerminalController.focus(pid: 100, directory: "/tmp/project", launchDirectory: nil, environment: env)

        // open -b should be called to activate the app
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.apple.Terminal"] })
        // AppleScript should select the right tab
        #expect(env.executedScripts.count >= 1)
        #expect(env.executedScripts[0].contains("tty of t is \"/dev/ttys001\""))
        // Should NOT use activateApp fallback
        #expect(env.activatedApps.isEmpty)
    }

    @Test("iTerm2 focus uses open -b then AppleScript")
    func itermRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [200: "com.googlecode.iterm2"]
        env.ttys = [200: "/dev/ttys005"]

        TerminalController.focus(pid: 200, directory: "/tmp/project", launchDirectory: nil, environment: env)

        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.googlecode.iterm2"] })
        #expect(env.executedScripts.count >= 1)
        #expect(env.executedScripts[0].contains("tty of s is \"/dev/ttys005\""))
    }

    @Test("VS Code focus uses open -b with launchDirectory then URI handler")
    func vscodeRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [300: "com.microsoft.VSCode"]

        TerminalController.focus(
            pid: 300,
            directory: "/tmp/worktree",
            launchDirectory: "/tmp/launch",
            environment: env
        )

        // open -b should use launchDirectory (not the worktree directory)
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.microsoft.VSCode", "/tmp/launch"] })
        // URI handler for terminal tab focus
        #expect(env.shellCommands.contains { $0.1.first?.starts(with: "vscode://") == true })
        // No shell command should reference the worktree directory
        #expect(!env.shellCommands.contains { $0.1.contains("/tmp/worktree") })
        // Should NOT use AppleScript
        #expect(env.executedScripts.isEmpty)
    }

    @Test("Cursor focus uses cursor:// URI scheme")
    func cursorRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [500: "com.todesktop.230313mzl4w4u92"]

        TerminalController.focus(
            pid: 500,
            directory: "/tmp/worktree",
            launchDirectory: "/tmp/launch",
            environment: env
        )

        // open -b should use launchDirectory (not the worktree directory)
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.todesktop.230313mzl4w4u92", "/tmp/launch"] })
        // URI handler should use cursor:// scheme, not vscode://
        #expect(env.shellCommands.contains { $0.1.first?.starts(with: "cursor://") == true })
        // No shell command should reference the worktree directory
        #expect(!env.shellCommands.contains { $0.1.contains("/tmp/worktree") })
        // Should NOT use AppleScript
        #expect(env.executedScripts.isEmpty)
    }

    @Test("VS Code focus falls back to directory when launchDirectory is nil")
    func vscodeFocusFallsBackToDirectoryWhenLaunchDirMissing() {
        let env = MockSystemEnvironment()
        env.guiApps = [300: "com.microsoft.VSCode"]

        TerminalController.focus(
            pid: 300,
            directory: "/tmp/project",
            launchDirectory: nil,
            environment: env
        )

        // When launchDirectory is nil, open -b falls back to directory
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.microsoft.VSCode", "/tmp/project"] })
        // URI handler still fires
        #expect(env.shellCommands.contains { $0.1.first?.starts(with: "vscode://") == true })
        // Should NOT use AppleScript
        #expect(env.executedScripts.isEmpty)
    }

    @Test("VS Code focus prefers hostWorkspaceFolder over launchDirectory")
    func vscodeFocusPrefersHostWorkspaceFolder() {
        let env = MockSystemEnvironment()
        env.guiApps = [300: "com.microsoft.VSCode"]

        TerminalController.focus(
            pid: 300,
            directory: "/tmp/worktree",
            launchDirectory: "/tmp/launch",
            hostWorkspaceFolder: "/tmp/host-workspace",
            environment: env
        )

        // open -b should use hostWorkspaceFolder (not launchDirectory or worktree)
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.microsoft.VSCode", "/tmp/host-workspace"] })
        #expect(!env.shellCommands.contains { $0.1.contains("/tmp/launch") })
        #expect(!env.shellCommands.contains { $0.1.contains("/tmp/worktree") })
        // URI handler still fires
        #expect(env.shellCommands.contains { $0.1.first?.starts(with: "vscode://") == true })
    }

    @Test("VS Code focus treats empty hostWorkspaceFolder as nil and falls back to launchDirectory")
    func vscodeFocusEmptyHostWorkspaceFolderFallsBack() {
        let env = MockSystemEnvironment()
        env.guiApps = [300: "com.microsoft.VSCode"]

        TerminalController.focus(
            pid: 300,
            directory: "/tmp/worktree",
            launchDirectory: "/tmp/launch",
            hostWorkspaceFolder: "",
            environment: env
        )

        // Empty hostWorkspaceFolder should be ignored; falls back to launchDirectory
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.microsoft.VSCode", "/tmp/launch"] })
        #expect(!env.shellCommands.contains { $0.1.contains("/tmp/worktree") })
    }

    @Test("Ghostty focus uses open -b then AppleScript with directory matching")
    func ghosttyRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [600: "com.mitchellh.ghostty"]
        env.ttys = [600: "/dev/ttys010"]

        TerminalController.focus(pid: 600, directory: "/tmp/project", launchDirectory: nil, environment: env)

        // open -b should be called to activate the app
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.mitchellh.ghostty"] })
        // AppleScript should match by working directory, not TTY
        #expect(env.executedScripts.count >= 1)
        #expect(env.executedScripts[0].contains("working directory of trm is \"/tmp/project\""))
        #expect(!env.executedScripts[0].contains("ttys010"))
    }

    @Test("Ghostty focus with windowId uses terminal ID matching")
    func ghosttyRoutingWithWindowId() {
        let env = MockSystemEnvironment()
        env.guiApps = [600: "com.mitchellh.ghostty"]
        env.ttys = [600: "/dev/ttys010"]

        TerminalController.focus(
            pid: 600,
            directory: "/tmp/project",
            launchDirectory: nil,
            bundleId: "com.mitchellh.ghostty",
            windowId: "F63A60A0-F28D-4FDC-8666-5844F57BDC1D",
            environment: env
        )

        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.mitchellh.ghostty"] })
        #expect(env.executedScripts.count >= 1)
        #expect(env.executedScripts[0].contains("id of trm is \"F63A60A0-F28D-4FDC-8666-5844F57BDC1D\""))
        // Script should also contain directory fallback (ID may be stale)
        #expect(env.executedScripts[0].contains("working directory"))
    }

    @Test("Warp focus uses open -b then AppleScript with TTY-based tab lookup")
    func warpRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [700: "dev.warp.Warp-Stable"]
        env.ttys = [700: "/dev/ttys003"]

        TerminalController.focus(pid: 700, directory: "/tmp/project", launchDirectory: nil, environment: env)

        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "dev.warp.Warp-Stable"] })
        #expect(env.executedScripts.count >= 1)
        #expect(env.executedScripts[0].contains("pgrep"))
        #expect(env.executedScripts[0].contains("ttys003"))
    }

    @Test("Unknown app uses generic AppleScript path")
    func unknownAppRouting() {
        let env = MockSystemEnvironment()
        env.guiApps = [400: "com.example.SomeApp"]
        env.appNames = [400: "SomeApp"]

        TerminalController.focus(pid: 400, directory: "/tmp/my-project", launchDirectory: nil, environment: env)

        // Should NOT use open -b
        #expect(env.shellCommands.isEmpty)
        // Should use generic System Events script
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("tell process \"SomeApp\""))
        #expect(env.executedScripts[0].contains("my-project"))
    }
}

// MARK: - Resume Command Tests

@Suite("TerminalController - buildResumeCommand")
struct BuildResumeCommandTests {

    private func makeSession(
        tool: SessionTool = .claude,
        conversationId: String? = "abc-123",
        launchArgs: String? = nil,
        hostAppBundleId: String? = nil,
        pid: Int? = 12345
    ) -> Session {
        Session(
            id: UUID().uuidString,
            conversationId: conversationId,
            tool: tool,
            directory: "/tmp/project",
            launchDirectory: nil,
            hostWorkspaceFolder: nil,
            lastAsk: nil,
            lastReply: nil,
            status: .idle,
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

    @Test("Claude with launchArgs and conversationId")
    func claudeWithArgs() {
        let session = makeSession(
            tool: .claude,
            conversationId: "abc-123",
            launchArgs: "--dangerously-skip-permissions"
        )
        let command = TerminalController.buildResumeCommand(session: session)
        #expect(command == "claude --dangerously-skip-permissions --resume abc-123")
    }

    @Test("Codex with launchArgs and conversationId")
    func codexWithArgs() {
        let session = makeSession(
            tool: .codex,
            conversationId: "def-456",
            launchArgs: "--full-auto"
        )
        let command = TerminalController.buildResumeCommand(session: session)
        #expect(command == "codex --full-auto resume def-456")
    }

    @Test("Gemini with no launchArgs")
    func geminiNoArgs() {
        let session = makeSession(
            tool: .gemini,
            conversationId: "ghi-789",
            launchArgs: nil
        )
        let command = TerminalController.buildResumeCommand(session: session)
        #expect(command == "gemini --resume ghi-789")
    }

    @Test("Empty string launchArgs produces no extra space")
    func emptyLaunchArgs() {
        let session = makeSession(
            tool: .claude,
            conversationId: "abc-123",
            launchArgs: ""
        )
        let command = TerminalController.buildResumeCommand(session: session)
        #expect(command == "claude --resume abc-123")
    }

    @Test("Nil conversationId returns nil")
    func nilConversationId() {
        let session = makeSession(
            tool: .claude,
            conversationId: nil
        )
        let command = TerminalController.buildResumeCommand(session: session)
        #expect(command == nil)
    }
}

// MARK: - Resume Script Tests

@Suite("TerminalController - buildResumeScript")
struct BuildResumeScriptTests {

    @Test("Terminal.app script contains do script and escaped command")
    func terminalScript() {
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp/project",
            app: .terminal
        )

        #expect(script != nil)
        #expect(script!.contains("do script"))
        #expect(script!.contains("claude --resume abc-123"))
        // Verify the new-tab sequence appears in correct order
        let keystrokeRange = script!.range(of: "keystroke \"t\" using command down")!
        let delayRange = script!.range(of: "delay 0.3")!
        let doScriptRange = script!.range(of: "selected tab of front window")!
        #expect(keystrokeRange.lowerBound < delayRange.lowerBound)
        #expect(delayRange.lowerBound < doScriptRange.lowerBound)
    }

    @Test("iTerm2 script contains write text and escaped command")
    func itermScript() {
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp/project",
            app: .iterm2
        )

        #expect(script != nil)
        #expect(script!.contains("write text"))
        #expect(script!.contains("claude --resume abc-123"))
    }

    @Test("Ghostty script uses native working directory and initial input")
    func ghosttyScript() {
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp/project",
            app: .ghostty
        )

        #expect(script != nil)
        #expect(script!.contains("tell application \"Ghostty\""))
        #expect(script!.contains("new surface configuration"))
        #expect(script!.contains("initial working directory of cfg to \"/tmp/project\""))
        #expect(script!.contains("initial input of cfg to \"claude --resume abc-123\" & return"))
        #expect(script!.contains("new tab in front window with configuration cfg"))
        #expect(script!.contains("new window with configuration cfg"))
    }

    @Test("Warp script uses System Events with keystroke for new tab and command execution")
    func warpScript() {
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp/project",
            app: .warp
        )

        #expect(script != nil)
        #expect(script!.contains("keystroke \"t\" using command down"))
        #expect(script!.contains("claude --resume abc-123"))
        #expect(script!.contains("keystroke return"))
        #expect(script!.contains("delay"))
    }

    @Test("Unknown bundle ID returns nil")
    func unknownBundleId() {
        let script = TerminalController.buildResumeScript(
            command: "claude --resume abc-123",
            directory: "/tmp/project",
            app: nil
        )

        #expect(script == nil)
    }

    @Test("Special characters in command are properly escaped")
    func specialCharactersEscaped() {
        let command = "claude --resume \"conv-123\" --flag 'value\\path'"
        let script = TerminalController.buildResumeScript(
            command: command,
            directory: "/tmp/project",
            app: .terminal
        )

        #expect(script != nil)
        // Quotes should be escaped for AppleScript
        #expect(script!.contains("\\\""))
        // Backslashes should be escaped for AppleScript
        #expect(script!.contains("\\\\"))
    }
}

// MARK: - Resume Routing Tests

@Suite("TerminalController - resume routing")
struct ResumeRoutingTests {

    @Test("Returns false when bundleId is nil")
    func nilBundleIdReturnsFalse() {
        let result = TerminalController.resume(
            command: "claude --resume abc-123",
            directory: "/tmp",
            bundleId: nil
        )
        #expect(result == false)
    }

    @Test("Ghostty resume uses open -b then AppleScript with surface configuration")
    func ghosttyResumeRouting() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.mitchellh.ghostty"]

        let result = TerminalController.resume(
            command: "claude --resume abc-123",
            directory: "/tmp",
            bundleId: "com.mitchellh.ghostty",
            environment: env
        )

        #expect(result == true)
        // open -b should be called to activate the app
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "com.mitchellh.ghostty"] })
        // AppleScript should use surface configuration with initial input (run after delay so check count)
        // The script is dispatched async after 0.3s, so it won't be in executedScripts immediately.
        // But open -b is called synchronously.
    }

    @Test("Warp resume uses open -b then returns true")
    func warpResumeRouting() {
        let env = MockSystemEnvironment()
        env.runningApps = ["dev.warp.Warp-Stable"]

        let result = TerminalController.resume(
            command: "claude --resume abc-123",
            directory: "/tmp",
            bundleId: "dev.warp.Warp-Stable",
            environment: env
        )

        #expect(result == true)
        #expect(env.shellCommands.contains { $0.0 == "/usr/bin/open" && $0.1 == ["-b", "dev.warp.Warp-Stable"] })
    }

    @Test("Returns false when directory does not exist")
    func nonexistentDirectoryReturnsFalse() {
        let result = TerminalController.resume(
            command: "claude --resume abc-123",
            directory: "/nonexistent/path/that/does/not/exist",
            bundleId: "com.apple.Terminal"
        )
        #expect(result == false)
    }
}

// MARK: - App Resolution Tests

@Suite("TerminalController - resolveAppBundleId", .serialized)
struct AppResolutionTests {

    private func makeSession(
        hostAppBundleId: String? = nil,
        pid: Int? = nil
    ) -> Session {
        Session(
            id: UUID().uuidString,
            conversationId: "abc-123",
            tool: .claude,
            directory: "/tmp/project",
            launchDirectory: nil,
            hostWorkspaceFolder: nil,
            lastAsk: nil,
            lastReply: nil,
            status: .idle,
            pid: pid,
            hostAppBundleId: hostAppBundleId,
            hostAppName: nil,
            windowId: nil,
            transcriptPath: nil,
            gitRepoName: nil,
            gitBranch: nil,
            launchArgs: nil,
            startedAt: Date(),
            updatedAt: Date(),
            lastReadAt: nil
        )
    }

    @Test("Uses DB bundleId when available")
    func usesDbBundleId() {
        let env = MockSystemEnvironment()

        let session = makeSession(hostAppBundleId: "com.apple.Terminal", pid: 100)
        let result = TerminalController.resolveAppBundleId(session: session, environment: env)
        #expect(result == "com.apple.Terminal")
    }

    @Test("Falls back to PID walk when no DB bundleId")
    func fallsBackToPidWalk() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200]
        env.guiApps = [200: "com.googlecode.iterm2"]

        let session = makeSession(hostAppBundleId: nil, pid: 100)
        let result = TerminalController.resolveAppBundleId(session: session, environment: env)
        #expect(result == "com.googlecode.iterm2")
    }

    @Test("Falls back to frontmost terminal when no PID")
    func fallsBackToFrontmostTerminal() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.apple.Terminal"]

        let session = makeSession(hostAppBundleId: nil, pid: nil)
        let result = TerminalController.resolveAppBundleId(session: session, environment: env)
        // detectFrontmostTerminal checks NSWorkspace.shared.frontmostApplication first,
        // then falls back to running apps matched against TerminalApp.all
        #expect(result == "com.apple.Terminal")
    }

    @Test("Returns nil when nothing available")
    func returnsNilWhenNothingAvailable() {
        let env = MockSystemEnvironment()
        env.runningApps = []

        let session = makeSession(hostAppBundleId: nil, pid: nil)
        let result = TerminalController.resolveAppBundleId(session: session, environment: env)
        #expect(result == nil)
    }
}
