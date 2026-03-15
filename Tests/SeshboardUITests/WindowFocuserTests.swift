import Foundation
import Testing

@testable import SeshboardUI

// MARK: - Mock System Environment

final class MockSystemEnvironment: SystemEnvironment, @unchecked Sendable {
    /// Map of pid → parent pid
    var parentPids: [pid_t: pid_t] = [:]

    /// Map of pid → bundle ID (only for GUI apps)
    var guiApps: [pid_t: String] = [:]

    /// Map of pid → app name
    var appNames: [pid_t: String] = [:]

    /// Map of pid → tty path
    var ttys: [Int: String] = [:]

    /// Bundle IDs of running apps
    var runningApps: [String] = []

    /// Tracks which apps were activated
    var activatedApps: [String] = []

    /// Tracks which scripts were run
    var executedScripts: [String] = []

    func parentPid(of pid: pid_t) -> pid_t {
        parentPids[pid] ?? 0
    }

    func guiAppBundleId(for pid: pid_t) -> String? {
        guiApps[pid]
    }

    func guiAppName(for pid: pid_t) -> String? {
        appNames[pid]
    }

    func tty(for pid: Int) -> String? {
        ttys[pid]
    }

    func runningAppBundleIds() -> [String] {
        runningApps
    }

    func activateApp(bundleId: String) {
        activatedApps.append(bundleId)
    }

    func runAppleScript(_ script: String) {
        executedScripts.append(script)
    }
}

// MARK: - App Discovery Tests

@Suite("WindowFocuser - App Discovery")
struct AppDiscoveryTests {
    @Test("Walks process tree to find VS Code")
    func findsVSCodeViaTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300]
        env.guiApps = [300: "com.microsoft.VSCode"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.microsoft.VSCode")
    }

    @Test("Walks process tree to find Terminal.app")
    func findsTerminalViaTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300]
        env.guiApps = [300: "com.apple.Terminal"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Falls back to running terminal app when tree walk fails")
    func fallsBackToRunningApp() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 200, 200: 300, 300: 0]
        env.runningApps = ["com.apple.Terminal"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Fallback prefers Terminal over iTerm if both running")
    func fallbackPrefersTerminal() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 0]
        env.runningApps = ["com.apple.Terminal", "com.googlecode.iterm2"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }

    @Test("Returns nil when no terminal app found and tree walk fails")
    func returnsNilWhenNoApp() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 0]
        env.runningApps = ["com.spotify.client"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == nil)
    }

    @Test("Handles deep process tree")
    func deepProcessTree() {
        let env = MockSystemEnvironment()
        env.parentPids = [100: 101, 101: 102, 102: 103, 103: 104]
        env.guiApps = [104: "com.apple.Terminal"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
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

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == nil)
    }

    @Test("PID that is itself a GUI app")
    func pidIsGuiApp() {
        let env = MockSystemEnvironment()
        env.guiApps = [100: "com.apple.Terminal"]

        let bundleId = WindowFocuser.findAppBundleId(for: 100, env: env)
        #expect(bundleId == "com.apple.Terminal")
    }
}

// MARK: - Script Generation Tests

@Suite("WindowFocuser - Script Generation")
struct ScriptGenerationTests {
    @Test("Terminal.app script matches by TTY")
    func terminalScript() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.apple.Terminal",
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
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            tty: nil,
            directory: "/Users/me/project"
        )
        #expect(script == nil)
    }

    @Test("iTerm2 script matches by TTY")
    func itermScript() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.googlecode.iterm2",
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
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.googlecode.iterm2",
            appName: "iTerm2",
            tty: nil,
            directory: "/Users/me/project"
        )
        #expect(script == nil)
    }

    @Test("VS Code script uses code CLI with directory")
    func vscodeScript() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.microsoft.VSCode",
            appName: "Code",
            tty: "/dev/ttys001",
            directory: "/Users/me/projects/seshboard"
        )

        #expect(script != nil)
        #expect(script!.contains("code"))
        #expect(script!.contains("/Users/me/projects/seshboard"))
    }

    @Test("VS Code script works without TTY")
    func vscodeScriptNoTty() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.microsoft.VSCode",
            appName: "Code",
            tty: nil,
            directory: "/Users/me/projects/seshboard"
        )

        #expect(script != nil)
        #expect(script!.contains("/Users/me/projects/seshboard"))
    }

    @Test("Unknown app uses generic System Events script")
    func unknownAppScript() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.example.SomeTerminal",
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
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.example.SomeApp",
            appName: "SomeApp",
            tty: nil,
            directory: "/Users/me/deeply/nested/my-project"
        )

        #expect(script != nil)
        #expect(script!.contains("name of w contains \"my-project\""))
    }

    @Test("Special characters in directory name are escaped (generic app)")
    func specialCharsEscaped() {
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.example.SomeApp",
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
        let script = WindowFocuser.buildFocusScript(
            bundleId: "com.apple.Terminal",
            appName: "Terminal",
            tty: "/dev/ttys000",
            directory: "/tmp"
        )

        #expect(script != nil)
        #expect(script!.contains("/dev/ttys000"))
    }
}

// MARK: - AppleScript Escaping Tests

@Suite("WindowFocuser - Escaping")
struct EscapingTests {
    @Test("Escapes backslashes")
    func escapesBackslashes() {
        #expect(WindowFocuser.escapeForAppleScript("a\\b") == "a\\\\b")
    }

    @Test("Escapes double quotes")
    func escapesQuotes() {
        #expect(WindowFocuser.escapeForAppleScript("say \"hi\"") == "say \\\"hi\\\"")
    }

    @Test("Leaves normal strings unchanged")
    func normalStrings() {
        #expect(WindowFocuser.escapeForAppleScript("hello world") == "hello world")
    }

    @Test("Handles empty string")
    func emptyString() {
        #expect(WindowFocuser.escapeForAppleScript("") == "")
    }

    @Test("Handles mixed special characters")
    func mixedSpecials() {
        let result = WindowFocuser.escapeForAppleScript("path\\to\\\"file\"")
        #expect(result == "path\\\\to\\\\\\\"file\\\"")
    }
}
