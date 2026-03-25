import AppKit
import Foundation
import SeshctlCore

public enum SessionResumer {

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
    public static func detectFrontmostTerminal(environment: SystemEnvironment = WindowFocuser.environment) -> String? {
        let running = environment.runningAppBundleIds()
        // Check frontmost first via NSWorkspace
        if let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           isKnownTerminalOrEditor(frontApp) {
            return frontApp
        }
        // Fall back to any running known terminal
        return (WindowFocuser.knownTerminals + Array(vsCodeBundleIds)).first { running.contains($0) }
    }

    // MARK: - Resume Execution

    /// Open the target app and execute a command in a new terminal tab.
    /// Returns true if the command was dispatched, false if fallback (clipboard) should be used.
    @discardableResult
    public static func resume(
        command: String,
        directory: String,
        bundleId: String?,
        environment: SystemEnvironment = WindowFocuser.environment
    ) -> Bool {
        guard let bundleId else { return false }
        guard FileManager.default.fileExists(atPath: directory) else { return false }

        if vsCodeBundleIds.contains(bundleId) {
            return resumeInVSCode(command: command, directory: directory, bundleId: bundleId, env: environment)
        }

        if let script = buildResumeScript(command: command, directory: directory, bundleId: bundleId) {
            // Bring the app forward first
            environment.runShellCommand("/usr/bin/open", args: ["-b", bundleId])
            // Small delay for app activation before sending AppleScript
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                environment.runAppleScript(script)
            }
            return true
        }

        return false
    }

    // MARK: - Private

    private static let vsCodeBundleIds: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
    ]

    private static func isKnownTerminalOrEditor(_ bundleId: String) -> Bool {
        WindowFocuser.knownTerminals.contains(bundleId) || vsCodeBundleIds.contains(bundleId)
    }

    private static func resumeInVSCode(
        command: String,
        directory: String,
        bundleId: String,
        env: SystemEnvironment
    ) -> Bool {
        let scheme: String
        switch bundleId {
        case "com.microsoft.VSCodeInsiders": scheme = "vscode-insiders"
        case "com.todesktop.230313mzl4w4u92": scheme = "cursor"
        default: scheme = "vscode"
        }

        // Open/focus the right VS Code window
        env.runShellCommand("/usr/bin/open", args: ["-b", bundleId, directory])

        // Send run-in-terminal URI after a brief delay for window activation
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

    // MARK: - Script Generation (internal for testing)

    /// Build AppleScript to open a new terminal tab and run a command.
    static func buildResumeScript(command: String, directory: String, bundleId: String) -> String? {
        let escapedCmd = WindowFocuser.escapeForAppleScript(command)
        let escapedDir = WindowFocuser.escapeForAppleScript(directory)
        let fullCmd = "cd \(escapedDir) && \(escapedCmd)"

        switch bundleId {
        case "com.apple.Terminal":
            return """
                tell application "Terminal"
                    activate
                    if (count of windows) > 0 then
                        do script "\(fullCmd)" in front window
                    else
                        do script "\(fullCmd)"
                    end if
                end tell
                """

        case "com.googlecode.iterm2":
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

        default:
            // Unknown terminal — can't execute commands
            return nil
        }
    }
}
