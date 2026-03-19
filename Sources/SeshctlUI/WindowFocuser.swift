import AppKit
import Foundation

// MARK: - System Environment Protocol

/// Abstracts system calls so WindowFocuser can be tested without real processes.
public protocol SystemEnvironment: Sendable {
    /// Get the parent PID of a process. Returns 0 on failure.
    func parentPid(of pid: pid_t) -> pid_t

    /// Get the bundle ID of the GUI app owning a PID, or nil if not a GUI app.
    func guiAppBundleId(for pid: pid_t) -> String?

    /// Get the localized name of the GUI app owning a PID.
    func guiAppName(for pid: pid_t) -> String?

    /// Get the TTY device path for a PID (e.g., "/dev/ttys000").
    func tty(for pid: Int) -> String?

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

// MARK: - Window Focuser

public enum WindowFocuser {
    nonisolated(unsafe) public static var environment: SystemEnvironment = RealSystemEnvironment()

    static let knownTerminals = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    private static let vsCodeBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    /// Activate the window belonging to the given PID and directory.
    public static func focus(pid: Int, directory: String) {
        let env = environment
        guard let bundleId = findAppBundleId(for: pid, env: env) else { return }

        if vsCodeBundleIds.contains(bundleId) {
            focusVSCode(pid: pid, directory: directory, bundleId: bundleId, env: env)
            return
        }

        if knownTerminals.contains(bundleId) {
            focusTerminal(pid: pid, directory: directory, bundleId: bundleId, env: env)
            return
        }

        let tty = env.tty(for: pid)
        if let script = buildFocusScript(
            bundleId: bundleId,
            appName: appName(for: pid, bundleId: bundleId, env: env),
            tty: tty,
            directory: directory
        ) {
            env.runAppleScript(script)
        } else {
            env.activateApp(bundleId: bundleId)
        }
    }

    /// Terminal apps: use `open -b` for reliable cross-Space switching,
    /// then AppleScript to select the correct tab (with a delayed retry).
    private static func focusTerminal(pid: Int, directory: String, bundleId: String, env: SystemEnvironment) {
        let tty = env.tty(for: pid)
        let name = appName(for: pid, bundleId: bundleId, env: env)

        // 1. Bring the app forward (handles cross-Space reliably)
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId])

        // 2. Select the right tab via AppleScript
        guard let script = buildFocusScript(
            bundleId: bundleId, appName: name, tty: tty, directory: directory
        ) else { return }

        env.runAppleScript(script)

        // 3. Retry after Space-switch animation completes
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            env.runAppleScript(script)
        }
    }

    /// VS Code: focus the right window via `open -b`, then focus the terminal tab via URI handler.
    private static func focusVSCode(pid: Int, directory: String, bundleId: String, env: SystemEnvironment) {
        let scheme = bundleId == "com.microsoft.VSCodeInsiders" ? "vscode-insiders" : "vscode"

        // 1. Focus the right VS Code window (fast, cross-Space)
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId, directory])

        // 2. Focus the terminal tab — send immediately (works same-Space),
        //    then again after a delay (catches cross-Space after animation)
        let uri = "\(scheme)://julo15.seshctl/focus-terminal?pid=\(pid)"
        env.runShellCommand("/usr/bin/open", args: [uri])
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            env.runShellCommand("/usr/bin/open", args: [uri])
        }
    }

    // MARK: - App Discovery (internal for testing)

    /// Walk the process tree to find the GUI app, with TTY-based fallback.
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
        return knownTerminals.first { running.contains($0) }
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

    // MARK: - Script Generation (internal for testing)

    /// Build the AppleScript to focus the right window. Returns nil if unable.
    /// Note: Terminal/iTerm2 scripts omit `activate` — callers must bring the
    /// app forward first (e.g. via `open -b`).
    static func buildFocusScript(
        bundleId: String,
        appName: String,
        tty: String?,
        directory: String
    ) -> String? {
        let dirName = (directory as NSString).lastPathComponent
        let escapedDirName = escapeForAppleScript(dirName)

        switch bundleId {
        case "com.apple.Terminal":
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

        case "com.googlecode.iterm2":
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

        default:
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

    static func escapeForAppleScript(_ s: String) -> String {
        var result = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Strip control characters that could break AppleScript string literals
        result.unicodeScalars.removeAll { scalar in
            scalar.properties.isNoncharacterCodePoint
                || (scalar.value < 0x20 && scalar != "\t")
                || scalar.value == 0x7F
        }
        result = result.replacingOccurrences(of: "\t", with: " ")
        return result
    }
}
