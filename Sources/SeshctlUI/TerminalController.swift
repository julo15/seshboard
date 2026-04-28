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

    /// Open a URL in the user's default handler (typically the default browser).
    func openURL(_ url: URL)
}

// MARK: - Real System Environment

public struct RealSystemEnvironment: SystemEnvironment {
    public init() {}

    public func parentPid(of pid: pid_t) -> pid_t {
        pid_t(RealProcessInfoProvider().parentPid(of: Int(pid)))
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
        do {
            try process.run()
        } catch {
            return
        }
        process.waitUntilExit()
    }

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Terminal Controller

public enum TerminalController {
    nonisolated(unsafe) public static var environment: SystemEnvironment = RealSystemEnvironment()

    // MARK: - Focus

    /// CANONICAL ENTRY POINT — all terminal focus actions MUST go through this method.
    /// Do not create parallel code paths.
    /// - Parameter hostWorkspaceFolder: Preferred input for URI-handler apps (VS Code family): the workspace folder of the VS Code window hosting the live terminal, recorded by the companion extension at terminal-open time. Takes precedence over `launchDirectory`. Ignored by AppleScript-based terminals.
    /// - Parameter launchDirectory: Original directory the session was launched in. Fallback for URI-handler apps when `hostWorkspaceFolder` is unavailable (e.g. sessions recorded before the extension was installed). Ignored by AppleScript-based terminals.
    public static func focus(pid: Int, directory: String, launchDirectory: String?, hostWorkspaceFolder: String? = nil, bundleId knownBundleId: String? = nil, windowId: String? = nil, environment env: SystemEnvironment? = nil) {
        let env = env ?? Self.environment
        guard let bundleId = knownBundleId ?? findAppBundleId(for: pid, env: env) else { return }

        if let app = TerminalApp.from(bundleId: bundleId) {
            if app.supportsURIHandler {
                // Precedence: hostWorkspaceFolder > launchDirectory > directory.
                let targetDir: String
                if let host = hostWorkspaceFolder, !host.isEmpty {
                    targetDir = host
                } else if let launch = launchDirectory, !launch.isEmpty {
                    targetDir = launch
                } else {
                    targetDir = directory
                }
                focusVSCode(pid: pid, directory: targetDir, bundleId: bundleId, env: env)
                return
            }
            if app.supportsAppleScriptFocus {
                focusTerminal(pid: pid, directory: directory, bundleId: bundleId, windowId: windowId, env: env)
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
            let sanitized = stripUnshellableFlags(args)
            if !sanitized.isEmpty {
                parts.append(sanitized)
            }
        }
        switch session.tool {
        case .codex:
            parts.append("resume")
        case .claude, .gemini:
            parts.append("--resume")
        }
        parts.append(conversationId)

        return parts.joined(separator: " ")
    }

    /// Strip launch flags whose values can't safely round-trip through a shell
    /// command string. `launchArgs` comes from `ps -o args=`, which discards
    /// the kernel argv boundaries — JSON values with embedded spaces, braces,
    /// and commas re-emerge as text that bash will brace-expand or word-split
    /// when pasted. Specifically:
    /// - `--session-id <UUID>`: cmux-injected per-launch random; useless for
    ///   resume since `--resume <conversationId>` already names the session.
    /// - `--settings <JSON>`: cmux-injected hook config; the new cmux tab will
    ///   re-inject hooks on its own spawn, so re-passing them is at best a
    ///   no-op and at worst a paste that mangles into nonsense.
    static func stripUnshellableFlags(_ args: String) -> String {
        var result = stripFlagWithUUIDValue(args, flag: "--session-id")
        result = stripFlagWithJSONValue(result, flag: "--settings")
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Remove `<flag> <UUID>` (8-4-4-4-12 hex form). Returns the input unchanged
    /// if the flag isn't present or isn't followed by a UUID-shaped token.
    static func stripFlagWithUUIDValue(_ args: String, flag: String) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag)) [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return args }
        let range = NSRange(args.startIndex..<args.endIndex, in: args)
        return regex.stringByReplacingMatches(in: args, range: range, withTemplate: "")
    }

    /// Remove `<flag> {…}` where the JSON value's end is found by brace
    /// counting with quote-state awareness. Returns the input unchanged if the
    /// flag isn't present, isn't followed by `{`, or has unbalanced braces.
    static func stripFlagWithJSONValue(_ args: String, flag: String) -> String {
        let prefix = "\(flag) "
        guard let prefixRange = args.range(of: prefix) else { return args }
        let valueStart = prefixRange.upperBound
        guard valueStart < args.endIndex, args[valueStart] == "{" else { return args }

        var depth = 0
        var inString = false
        var escaped = false
        var i = valueStart
        while i < args.endIndex {
            let c = args[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let valueEnd = args.index(after: i)
                    var result = args
                    result.removeSubrange(prefixRange.lowerBound..<valueEnd)
                    return result
                }
            }
            i = args.index(after: i)
        }
        return args
    }

    /// Build a fork command from a session's stored data.
    /// Returns nil for non-Claude tools or when the session has no conversationId.
    /// `--fork-session` is a Claude-only flag and only valid alongside `--resume`.
    public static func buildForkCommand(session: Session) -> String? {
        guard session.tool == .claude else { return nil }
        guard let resume = buildResumeCommand(session: session) else { return nil }
        return resume + " --fork-session"
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
        directory: String,
        windowId: String? = nil
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

        case .ghostty:
            let escapedDir = escapeForAppleScript(directory)
            // Try terminal ID first (exact match), then fall back to directory matching.
            // The ID may be stale after resume (new tab gets a new ID), so both paths
            // are always included in the script.
            let idMatchBlock: String
            if let windowId {
                let escapedId = escapeForAppleScript(windowId)
                idMatchBlock = """
                        -- Try exact terminal ID match first
                        repeat with w in windows
                            repeat with t in tabs of w
                                repeat with trm in terminals of t
                                    if id of trm is "\(escapedId)" then
                                        select tab t
                                        activate window w
                                        return
                                    end if
                                end repeat
                            end repeat
                        end repeat
                    """
            } else {
                idMatchBlock = ""
            }
            return """
                tell application "Ghostty"
                \(idMatchBlock)
                    -- Fall back to directory matching: prefer selected tab, then scan all
                    if (count of windows) > 0 then
                        set selTab to selected tab of front window
                        repeat with trm in terminals of selTab
                            if working directory of trm is "\(escapedDir)" then
                                activate window (front window)
                                return
                            end if
                        end repeat
                    end if
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with trm in terminals of t
                                if working directory of trm is "\(escapedDir)" then
                                    select tab t
                                    activate window w
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """

        case .warp:
            if let tty {
                let ttyName = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
                let escapedTtyName = escapeForAppleScript(ttyName)
                return """
                    set ttyName to "\(escapedTtyName)"
                    set shellScript to "H=$(pgrep -P $(pgrep -f 'Warp.app/Contents/MacOS/stable' | head -1) | head -1) 2>/dev/null; pgrep -P $H 2>/dev/null | xargs ps -o tty= -p 2>/dev/null | tr -d ' ' | sort | grep -n " & quoted form of ttyName & " | head -1 | cut -d: -f1"
                    try
                        set tabPos to (do shell script shellScript) as integer
                    on error
                        set tabPos to 0
                    end try
                    delay 0.3
                    tell application "System Events"
                        tell process "Warp"
                            if tabPos > 0 and tabPos < 10 then
                                keystroke (tabPos as text) using command down
                            end if
                        end tell
                    end tell
                    """
            }
            // No TTY available — fall back to window name matching
            return """
                tell application "System Events"
                    tell process "Warp"
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

        case .cmux:
            // cmux's AppleScript model is two-level: each `window` contains
            // `tab`s (vertical-list workspaces, id = $CMUX_WORKSPACE_ID) and
            // each tab contains `terminal`s (horizontal tabs within a
            // workspace, id = $CMUX_SURFACE_ID). We pack both UUIDs into
            // `windowId` as "<workspace>|<surface>". The outer repeat selects
            // the right workspace; a nested repeat then `focus`es the matching
            // terminal so the horizontal tab is raised too. Backward-compat:
            // pre-upgrade sessions stored just the workspace UUID with no
            // pipe, so we skip the inner block when the surface part is
            // missing or empty.
            guard let windowId else { return nil }
            // We pack workspace+surface UUIDs as `<ws>|<sf>` in the single windowId column.
            // `|` is safe because UUIDs can't contain it; picked over a non-printing separator
            // or JSON for DB-row readability.
            let separatorIndex = windowId.firstIndex(of: "|")
            let workspaceId: String
            let surfaceId: String?
            if let separatorIndex {
                workspaceId = String(windowId[..<separatorIndex])
                let rawSurface = String(windowId[windowId.index(after: separatorIndex)...])
                let trimmed = rawSurface.trimmingCharacters(in: .whitespacesAndNewlines)
                surfaceId = trimmed.isEmpty ? nil : trimmed
            } else {
                workspaceId = windowId
                surfaceId = nil
            }
            let escapedWorkspaceId = escapeForAppleScript(workspaceId)
            let surfaceBlock: String
            if let surfaceId {
                let escapedSurfaceId = escapeForAppleScript(surfaceId)
                surfaceBlock = """

                                repeat with tr in terminals of t
                                    if id of tr is "\(escapedSurfaceId)" then
                                        focus tr
                                        return
                                    end if
                                end repeat
                """
            } else {
                surfaceBlock = ""
            }
            return """
                tell application "cmux"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            if id of t is "\(escapedWorkspaceId)" then
                                activate window w
                                select tab t\(surfaceBlock)
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """

        case .vscode, .vscodeInsiders, .cursor, nil:
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

        case .ghostty:
            return """
                tell application "Ghostty"
                    set cfg to new surface configuration
                    set initial working directory of cfg to "\(escapedDir)"
                    set initial input of cfg to "\(escapedCmd)" & return
                    if (count of windows) > 0 then
                        new tab in front window with configuration cfg
                    else
                        new window with configuration cfg
                    end if
                end tell
                """

        case .warp:
            return """
                tell application "System Events"
                    tell process "Warp"
                        keystroke "t" using command down
                        delay 0.5
                        keystroke "\(fullCmd)"
                        delay 0.1
                        keystroke return
                    end tell
                end tell
                """

        case .cmux:
            // cmux's AppleScript surface exposes `new tab` returning a tab with
            // a `focused terminal`; `input text` pastes into the shell. We emit
            // the shell payload with a POSIX-escaped `cd`, then append `& return`
            // in AppleScript so the newline survives `escapeForAppleScript`
            // (which strips literal linefeeds).
            let shellPayload = SessionAction.compoundShellCommand(command, directory: directory)
            let escapedPayload = escapeForAppleScript(shellPayload)
            return """
                tell application "cmux"
                    activate
                    try
                        set w to front window
                    on error
                        set w to (new window)
                    end try
                    set t to (new tab in w)
                    select tab t
                    input text ("\(escapedPayload)" & return) to focused terminal of t
                end tell
                """

        case .vscode, .vscodeInsiders, .cursor, nil:
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

    private static func focusTerminal(pid: Int, directory: String, bundleId: String, windowId: String? = nil, env: SystemEnvironment) {
        let tty = env.tty(for: pid)
        let name = appName(for: pid, bundleId: bundleId, env: env)

        // 1. Bring the app forward (handles cross-Space reliably)
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId])

        // 2. Select the right tab via AppleScript
        guard let script = buildFocusScript(
            app: TerminalApp.from(bundleId: bundleId), appName: name, tty: tty, directory: directory, windowId: windowId
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
