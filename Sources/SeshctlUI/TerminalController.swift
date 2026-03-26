import AppKit
import Foundation
import SeshctlCore

// MARK: - System Environment Protocol

/// Abstracts system calls so TerminalController can be tested without real processes.
public protocol SystemEnvironment: Sendable {
    /// Get the parent PID of a process. Returns 0 on failure.
    func parentPid(of pid: pid_t) -> pid_t

    /// Get the bundle ID of the GUI app owning a PID, or nil if not a GUI app.
    func guiAppBundleId(for pid: pid_t) -> String?

    /// Get the localized name of the GUI app owning a PID.
    func guiAppName(for pid: pid_t) -> String?

    /// Get the TTY device path for a PID (e.g., "/dev/ttys000").
    func tty(for pid: Int) -> String?

    /// Get the bundle ID of the frontmost application, or nil.
    func frontmostAppBundleId() -> String?

    /// Get bundle IDs of all currently running apps.
    func runningAppBundleIds() -> [String]

    /// Activate the app with the given bundle ID.
    func activateApp(bundleId: String)

    /// Run an AppleScript string.
    func runAppleScript(_ script: String)

    /// Run a shell command with arguments.
    func runShellCommand(_ path: String, args: [String])
}

// MARK: - Real System Environment

public struct RealSystemEnvironment: SystemEnvironment {
    public init() {}

    public func parentPid(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }

    public func guiAppBundleId(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return nil }
        return app.bundleIdentifier
    }

    public func guiAppName(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    public func tty(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "tty="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let tty = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tty, !tty.isEmpty else { return nil }
        return "/dev/\(tty)"
    }

    public func frontmostAppBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func runningAppBundleIds() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    public func activateApp(bundleId: String) {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleId }?
            .activate()
    }

    public func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    public func runShellCommand(_ path: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - Terminal Controller

public enum TerminalController {
    nonisolated(unsafe) public static var environment: SystemEnvironment = RealSystemEnvironment()

    // MARK: - Focus

    /// CANONICAL ENTRY POINT — all terminal focus actions MUST go through this method.
    /// Do not create parallel code paths.
    public static func focus(pid: Int, directory: String, environment env: SystemEnvironment? = nil) {
        let env = env ?? Self.environment
        guard let bundleId = findAppBundleId(for: pid, env: env) else { return }

        if let app = TerminalApp.from(bundleId: bundleId) {
            if app.supportsURIHandler {
                focusVSCode(pid: pid, directory: directory, bundleId: bundleId, env: env)
                return
            }
            if app.supportsTTYFocus {
                focusTerminal(pid: pid, directory: directory, bundleId: bundleId, env: env)
                return
            }
        }

        // Generic fallback for unknown apps
        let tty = env.tty(for: pid)
        if let script = buildFocusScript(
            app: TerminalApp.from(bundleId: bundleId),
            appName: appName(for: pid, bundleId: bundleId, env: env),
            tty: tty,
            directory: directory
        ) {
            env.runAppleScript(script)
        } else {
            env.activateApp(bundleId: bundleId)
        }
    }

    // MARK: - Resume

    /// CANONICAL ENTRY POINT — all terminal resume actions MUST go through this method.
    /// Do not create parallel code paths.
    @discardableResult
    public static func resume(
        command: String,
        directory: String,
        bundleId: String?,
        environment env: SystemEnvironment? = nil
    ) -> Bool {
        let env = env ?? Self.environment
        guard let bundleId else { return false }
        guard FileManager.default.fileExists(atPath: directory) else { return false }

        if let app = TerminalApp.from(bundleId: bundleId) {
            if app.supportsURIHandler {
                return resumeInVSCode(command: command, directory: directory, bundleId: bundleId, env: env)
            }
            if app.supportsAppleScriptResume {
                return resumeInTerminal(command: command, directory: directory, bundleId: bundleId, env: env)
            }
        }

        return false
    }

    // MARK: - Resume Command Building

    /// Build a resume command from a session's stored data.
    /// Returns nil if the session has no conversationId.
    public static func buildResumeCommand(session: Session) -> String? {
        guard let conversationId = session.conversationId else { return nil }

        let binary: String
        switch session.tool {
        case .claude: binary = "claude"
        case .gemini: binary = "gemini"
        case .codex: binary = "codex"
        }

        var parts = [binary]
        if let args = session.launchArgs, !args.isEmpty {
            parts.append(args)
        }
        parts.append("--resume")
        parts.append(conversationId)

        return parts.joined(separator: " ")
    }

    // MARK: - Frontmost Terminal Detection

    /// Find the frontmost known terminal app. Returns its bundle ID, or nil if none running.
    public static func detectFrontmostTerminal(environment env: SystemEnvironment? = nil) -> String? {
        let env = env ?? Self.environment
        let running = env.runningAppBundleIds()
        if let frontApp = env.frontmostAppBundleId(),
           TerminalApp.from(bundleId: frontApp) != nil {
            return frontApp
        }
        return TerminalApp.allCases.map(\.bundleId).first { running.contains($0) }
    }

    // MARK: - Unified App Resolution

    /// Resolve the best bundle ID for a session: DB value, then PID walk, then frontmost terminal.
    public static func resolveAppBundleId(session: Session, environment env: SystemEnvironment? = nil) -> String? {
        let env = env ?? Self.environment
        if let bundleId = session.hostAppBundleId, !bundleId.isEmpty {
            return bundleId
        }
        if let pid = session.pid, let bundleId = findAppBundleId(for: pid, env: env) {
            return bundleId
        }
        return detectFrontmostTerminal(environment: env)
    }

    // MARK: - App Discovery (internal for testing)

    /// Walk the process tree to find the GUI app, with fallback to running known terminals.
    static func findAppBundleId(for pid: Int, env: SystemEnvironment) -> String? {
        var currentPid = pid_t(pid)
        for _ in 0..<10 {
            if let bundleId = env.guiAppBundleId(for: currentPid) {
                return bundleId
            }
            let parent = env.parentPid(of: currentPid)
            if parent <= 1 || parent == currentPid { break }
            currentPid = parent
        }

        // Fallback: check if any known terminal app is running
        let running = Set(env.runningAppBundleIds())
        return TerminalApp.allCases.map(\.bundleId).first { running.contains($0) }
    }

    // MARK: - Script Generation (internal for testing)

    /// Build the AppleScript to focus the right window. Returns nil if unable.
    /// Note: Terminal/iTerm2 scripts omit `activate` — callers must bring the
    /// app forward first (e.g. via `open -b`).
    static func buildFocusScript(
        app: TerminalApp?,
        appName: String,
        tty: String?,
        directory: String
    ) -> String? {
        let dirName = (directory as NSString).lastPathComponent
        let escapedDirName = escapeForAppleScript(dirName)

        switch app {
        case .terminal:
            guard let tty else { return nil }
            let escapedTty = escapeForAppleScript(tty)
            return """
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(escapedTty)" then
                                set selected of t to true
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """

        case .iterm2:
            guard let tty else { return nil }
            let escapedTty = escapeForAppleScript(tty)
            return """
                tell application "iTerm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(escapedTty)" then
                                    select s
                                    select w
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """

        case .warp, .vscode, .vscodeInsiders, .cursor, nil:
            let escapedName = escapeForAppleScript(appName)
            return """
                tell application "System Events"
                    tell process "\(escapedName)"
                        set frontmost to true
                        set targetWindow to missing value
                        repeat with w in windows
                            if name of w contains "\(escapedDirName)" then
                                set targetWindow to w
                                exit repeat
                            end if
                        end repeat
                        if targetWindow is not missing value then
                            perform action "AXRaise" of targetWindow
                        end if
                    end tell
                end tell
                """
        }
    }

    /// Build AppleScript to open a new terminal tab and run a command.
    static func buildResumeScript(command: String, directory: String, app: TerminalApp?) -> String? {
        let escapedCmd = escapeForAppleScript(command)
        let escapedDir = escapeForAppleScript(directory)
        let fullCmd = "cd \(escapedDir) && \(escapedCmd)"

        switch app {
        case .terminal:
            // Terminal.app has no native AppleScript "create tab" API (unlike iTerm2's
            // `create tab with default profile`), so we simulate Cmd+T via System Events.
            return """
                tell application "Terminal"
                    activate
                    if (count of windows) > 0 then
                        tell application "System Events" to keystroke "t" using command down
                        delay 0.3
                        do script "\(fullCmd)" in selected tab of front window
                    else
                        do script "\(fullCmd)"
                    end if
                end tell
                """

        case .iterm2:
            return """
                tell application "iTerm2"
                    if (count of windows) > 0 then
                        tell current window
                            set newTab to (create tab with default profile)
                            tell current session of newTab
                                write text "\(fullCmd)"
                            end tell
                        end tell
                    else
                        create window with default profile
                        tell current session of current window
                            write text "\(fullCmd)"
                        end tell
                    end if
                end tell
                """

        case .warp, .vscode, .vscodeInsiders, .cursor, nil:
            // Unknown/unsupported terminal — can't execute commands via AppleScript
            return nil
        }
    }

    static func escapeForAppleScript(_ s: String) -> String {
        var result = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        result.unicodeScalars.removeAll { scalar in
            scalar.properties.isNoncharacterCodePoint
                || (scalar.value < 0x20 && scalar != "\t")
                || scalar.value == 0x7F
        }
        result = result.replacingOccurrences(of: "\t", with: " ")
        return result
    }

    // MARK: - Private Helpers

    private static func focusTerminal(pid: Int, directory: String, bundleId: String, env: SystemEnvironment) {
        let tty = env.tty(for: pid)
        let name = appName(for: pid, bundleId: bundleId, env: env)

        // 1. Bring the app forward (handles cross-Space reliably)
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId])

        // 2. Select the right tab via AppleScript
        guard let script = buildFocusScript(
            app: TerminalApp.from(bundleId: bundleId), appName: name, tty: tty, directory: directory
        ) else { return }

        env.runAppleScript(script)

        // 3. Retry after Space-switch animation completes
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            env.runAppleScript(script)
        }
    }

    private static func focusVSCode(pid: Int, directory: String, bundleId: String, env: SystemEnvironment) {
        let scheme = TerminalApp.from(bundleId: bundleId)?.uriScheme ?? "vscode"
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId, directory])
        let uri = "\(scheme)://julo15.seshctl/focus-terminal?pid=\(pid)"
        env.runShellCommand("/usr/bin/open", args: [uri])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            env.runShellCommand("/usr/bin/open", args: [uri])
        }
    }

    private static func resumeInVSCode(
        command: String,
        directory: String,
        bundleId: String,
        env: SystemEnvironment
    ) -> Bool {
        let scheme = TerminalApp.from(bundleId: bundleId)?.uriScheme ?? "vscode"
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId, directory])
        var queryAllowed = CharacterSet.urlQueryAllowed
        queryAllowed.remove(charactersIn: "&=+#")
        guard let encodedCmd = command.addingPercentEncoding(withAllowedCharacters: queryAllowed),
              let encodedDir = directory.addingPercentEncoding(withAllowedCharacters: queryAllowed) else {
            return false
        }
        let uri = "\(scheme)://julo15.seshctl/run-in-terminal?cmd=\(encodedCmd)&cwd=\(encodedDir)"
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            env.runShellCommand("/usr/bin/open", args: [uri])
        }
        return true
    }

    private static func resumeInTerminal(
        command: String,
        directory: String,
        bundleId: String,
        env: SystemEnvironment
    ) -> Bool {
        guard let script = buildResumeScript(command: command, directory: directory, app: TerminalApp.from(bundleId: bundleId)) else {
            return false
        }
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            env.runAppleScript(script)
        }
        return true
    }

    private static func appName(for pid: Int, bundleId: String, env: SystemEnvironment) -> String {
        var currentPid = pid_t(pid)
        for _ in 0..<10 {
            if let name = env.guiAppName(for: currentPid) {
                return name
            }
            let parent = env.parentPid(of: currentPid)
            if parent <= 1 || parent == currentPid { break }
            currentPid = parent
        }
        return bundleId
    }
}
