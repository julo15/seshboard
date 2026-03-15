import AppKit
import Foundation

public enum WindowFocuser {
    /// Activate the window belonging to the given PID.
    /// Uses NSRunningApplication to find the app, then AppleScript to bring the specific window forward.
    public static func focus(pid: Int) {
        // Find the app that owns this process (could be the PID itself or its parent)
        // CLI tools like claude/gemini run inside Terminal.app, VS Code terminal, etc.
        // The PID is the CLI process, but we need to activate the terminal app that contains it.
        guard let app = findTerminalApp(for: pid) else { return }

        // Activate the app
        app.activate()

        // Use AppleScript to bring the specific window to front
        focusWindowViaAppleScript(app: app, pid: pid)
    }

    private static func findTerminalApp(for pid: Int) -> NSRunningApplication? {
        // Walk up the process tree to find the GUI app (Terminal, iTerm, VS Code, etc.)
        var currentPid = pid_t(pid)

        for _ in 0..<10 {  // max depth to avoid infinite loops
            if let app = NSRunningApplication(processIdentifier: currentPid),
               app.activationPolicy == .regular {
                return app
            }

            // Get parent PID
            let parentPid = getParentPid(currentPid)
            if parentPid <= 1 || parentPid == currentPid { break }
            currentPid = parentPid
        }

        return nil
    }

    private static func getParentPid(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }

    private static func focusWindowViaAppleScript(app: NSRunningApplication, pid: Int) {
        guard let bundleId = app.bundleIdentifier else { return }

        // For Terminal.app, we can find the tab/window by looking for the process
        let script: String
        switch bundleId {
        case "com.apple.Terminal":
            script = """
                tell application "Terminal"
                    activate
                    set targetWindow to missing value
                    repeat with w in windows
                        repeat with t in tabs of w
                            try
                                set procs to processes of t
                                repeat with p in procs
                                    if p contains "\(pid)" then
                                        set targetWindow to w
                                        exit repeat
                                    end if
                                end repeat
                            end try
                            if targetWindow is not missing value then exit repeat
                        end repeat
                        if targetWindow is not missing value then exit repeat
                    end repeat
                    if targetWindow is not missing value then
                        set index of targetWindow to 1
                    end if
                end tell
                """
        case "com.googlecode.iterm2":
            script = """
                tell application "iTerm2"
                    activate
                end tell
                """
        default:
            // Generic: just activate the app (covers VS Code, Warp, etc.)
            script = """
                tell application id "\(bundleId)"
                    activate
                end tell
                """
        }

        // Run async to not block the UI
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}
