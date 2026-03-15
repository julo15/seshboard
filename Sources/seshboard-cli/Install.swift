import ArgumentParser
import Foundation

// MARK: - Install

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install seshboard hooks into LLM CLI configs."
    )

    @Flag(help: "Install Claude Code hooks.")
    var claude = false

    @Flag(help: "Install all supported CLI hooks.")
    var all = false

    func run() throws {
        let installClaude = claude || all

        if !installClaude {
            throw ValidationError("Specify --claude or --all.")
        }

        if installClaude {
            try installClaudeHooks()
        }
    }
}

// MARK: - Uninstall

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove seshboard hooks from LLM CLI configs."
    )

    @Flag(help: "Uninstall Claude Code hooks.")
    var claude = false

    @Flag(help: "Uninstall all supported CLI hooks.")
    var all = false

    func run() throws {
        let uninstallClaude = claude || all

        if !uninstallClaude {
            throw ValidationError("Specify --claude or --all.")
        }

        if uninstallClaude {
            try uninstallClaudeHooks()
        }
    }
}

// MARK: - Claude Code Hook Installation

private let hooksDir = NSString(
    string: "~/.local/share/seshboard/hooks/claude"
).expandingTildeInPath

private let claudeSettingsPath = NSString(
    string: "~/.claude/settings.json"
).expandingTildeInPath

/// The hook entries seshboard adds to Claude Code settings.
private let seshboardHookEntries: [(event: String, matcher: String, command: String)] = [
    ("SessionStart", "", "\(hooksDir)/session-start.sh"),
    ("UserPromptSubmit", "", "\(hooksDir)/user-prompt.sh"),
    ("Stop", "", "\(hooksDir)/stop.sh"),
    ("SessionEnd", "", "\(hooksDir)/session-end.sh"),
]

private func installClaudeHooks() throws {
    // 1. Install hook scripts
    try installHookScripts()

    // 2. Back up existing settings
    try backupClaudeSettings()

    // 3. Inject hook entries into settings.json
    try injectClaudeHookEntries()

    print("Claude Code: added hooks to \(claudeSettingsPath)")
    print("Hook scripts installed to \(hooksDir)/")
}

private func uninstallClaudeHooks() throws {
    // Remove hook entries from settings.json
    try removeClaudeHookEntries()

    // Remove hook scripts
    let fm = FileManager.default
    if fm.fileExists(atPath: hooksDir) {
        try fm.removeItem(atPath: hooksDir)
    }

    print("Claude Code: removed seshboard hooks from \(claudeSettingsPath)")
}

private func installHookScripts() throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

    // Find the bundled hook scripts relative to the executable
    // For development, look in the source tree; for installed binary, look in the same dir
    let sourceHooksDir = findSourceHooksDir()

    let scripts = ["session-start.sh", "user-prompt.sh", "stop.sh", "session-end.sh"]
    for script in scripts {
        let src = (sourceHooksDir as NSString).appendingPathComponent(script)
        let dst = (hooksDir as NSString).appendingPathComponent(script)

        guard fm.fileExists(atPath: src) else {
            throw ValidationError("Hook script not found: \(src)")
        }

        if fm.fileExists(atPath: dst) {
            try fm.removeItem(atPath: dst)
        }
        try fm.copyItem(atPath: src, toPath: dst)

        // Ensure executable
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
    }
}

private func findSourceHooksDir() -> String {
    // Look relative to the executable for a hooks/claude directory
    let execDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
    let candidates = [
        (execDir as NSString).appendingPathComponent("../../hooks/claude"),
        (execDir as NSString).appendingPathComponent("../hooks/claude"),
        (execDir as NSString).appendingPathComponent("hooks/claude"),
        // When running from swift build, the binary is in .build/debug/
        (execDir as NSString).appendingPathComponent("../../../hooks/claude"),
    ]

    let fm = FileManager.default
    for candidate in candidates {
        let resolved = (candidate as NSString).standardizingPath
        if fm.fileExists(atPath: resolved) {
            return resolved
        }
    }

    // Fallback: current directory
    return (fm.currentDirectoryPath as NSString).appendingPathComponent("hooks/claude")
}

private func backupClaudeSettings() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: claudeSettingsPath) else { return }

    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let backupPath = claudeSettingsPath + ".bak-\(timestamp)"
    try fm.copyItem(atPath: claudeSettingsPath, toPath: backupPath)
}

private func injectClaudeHookEntries() throws {
    let fm = FileManager.default
    var settings: [String: Any] = [:]

    if fm.fileExists(atPath: claudeSettingsPath) {
        let data = try Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath))
        settings =
            try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    var hooks = settings["hooks"] as? [String: Any] ?? [:]

    for entry in seshboardHookEntries {
        var eventHooks = hooks[entry.event] as? [[String: Any]] ?? []

        // Check if seshboard hook already exists for this event
        let alreadyExists = eventHooks.contains { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshboard")
            }
        }

        if !alreadyExists {
            let hookGroup: [String: Any] = [
                "matcher": entry.matcher,
                "hooks": [
                    [
                        "type": "command",
                        "command": entry.command,
                    ] as [String: Any]
                ],
            ]
            eventHooks.append(hookGroup)
        }

        hooks[entry.event] = eventHooks
    }

    settings["hooks"] = hooks

    let data = try JSONSerialization.data(
        withJSONObject: settings,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: URL(fileURLWithPath: claudeSettingsPath))
}

private func removeClaudeHookEntries() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: claudeSettingsPath) else { return }

    let data = try Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath))
    guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    guard var hooks = settings["hooks"] as? [String: Any] else { return }

    for entry in seshboardHookEntries {
        guard var eventHooks = hooks[entry.event] as? [[String: Any]] else { continue }

        eventHooks.removeAll { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshboard")
            }
        }

        if eventHooks.isEmpty {
            hooks.removeValue(forKey: entry.event)
        } else {
            hooks[entry.event] = eventHooks
        }
    }

    if hooks.isEmpty {
        settings.removeValue(forKey: "hooks")
    } else {
        settings["hooks"] = hooks
    }

    let updatedData = try JSONSerialization.data(
        withJSONObject: settings,
        options: [.prettyPrinted, .sortedKeys]
    )
    try updatedData.write(to: URL(fileURLWithPath: claudeSettingsPath))
}
