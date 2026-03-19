import ArgumentParser
import Foundation

// MARK: - Install

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install seshctl hooks into LLM CLI configs."
    )

    @Flag(help: "Install Claude Code hooks.")
    var claude = false

    @Flag(help: "Install Codex hooks.")
    var codex = false

    @Flag(help: "Install all supported CLI hooks.")
    var all = false

    func run() throws {
        let installClaude = claude || all
        let installCodex = codex || all

        if !installClaude && !installCodex {
            throw ValidationError("Specify --claude, --codex, or --all.")
        }

        if installClaude {
            try installClaudeHooks()
        }

        if installCodex {
            try installCodexHooks()
        }
    }
}

// MARK: - Uninstall

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove seshctl hooks from LLM CLI configs."
    )

    @Flag(help: "Uninstall Claude Code hooks.")
    var claude = false

    @Flag(help: "Uninstall Codex hooks.")
    var codex = false

    @Flag(help: "Uninstall all supported CLI hooks.")
    var all = false

    func run() throws {
        let uninstallClaude = claude || all
        let uninstallCodex = codex || all

        if !uninstallClaude && !uninstallCodex {
            throw ValidationError("Specify --claude, --codex, or --all.")
        }

        if uninstallClaude {
            try uninstallClaudeHooks()
        }

        if uninstallCodex {
            try uninstallCodexHooks()
        }
    }
}

// MARK: - Claude Code Hook Installation

private let hooksDir = NSString(
    string: "~/.local/share/seshctl/hooks/claude"
).expandingTildeInPath

private let claudeSettingsPath = NSString(
    string: "~/.claude/settings.json"
).expandingTildeInPath

/// The hook entries seshctl adds to Claude Code settings.
private let seshctlHookEntries: [(event: String, matcher: String, command: String)] = [
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
    // Back up existing settings before modifying
    try backupClaudeSettings()

    // Remove hook entries from settings.json
    try removeClaudeHookEntries()

    // Remove hook scripts
    let fm = FileManager.default
    if fm.fileExists(atPath: hooksDir) {
        try fm.removeItem(atPath: hooksDir)
    }

    print("Claude Code: removed seshctl hooks from \(claudeSettingsPath)")
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
    try backupFile(atPath: claudeSettingsPath)
}

private func backupCodexSettings() throws {
    try backupFile(atPath: codexSettingsPath)
}

private func backupFile(atPath path: String) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return }

    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
    let backupPath = path + ".bak-\(timestamp)"
    try fm.copyItem(atPath: path, toPath: backupPath)
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

    for entry in seshctlHookEntries {
        var eventHooks = hooks[entry.event] as? [[String: Any]] ?? []

        // Check if seshctl hook already exists for this event
        let alreadyExists = eventHooks.contains { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshctl")
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

    for entry in seshctlHookEntries {
        guard var eventHooks = hooks[entry.event] as? [[String: Any]] else { continue }

        eventHooks.removeAll { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshctl")
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

// MARK: - Codex Hook Installation

private let codexHooksDir = NSString(
    string: "~/.local/share/seshctl/hooks/codex"
).expandingTildeInPath

private let codexSettingsPath = NSString(
    string: "~/.agents/hooks.json"
).expandingTildeInPath

private let codexConfigPath = NSString(
    string: "~/.agents/config.toml"
).expandingTildeInPath

/// The hook entries seshctl adds to Codex settings.
private let seshctlCodexHookEntries: [(event: String, matcher: String, command: String)] = [
    ("SessionStart", "", "\(codexHooksDir)/session-start.sh"),
    ("UserPromptSubmit", "", "\(codexHooksDir)/user-prompt.sh"),
    ("Stop", "", "\(codexHooksDir)/stop.sh"),
]

private func installCodexHooks() throws {
    // 1. Install hook scripts
    try installCodexHookScripts()

    // 2. Back up existing settings
    try backupCodexSettings()

    // 3. Inject hook entries into hooks.json
    try injectCodexHookEntries()

    // 4. Set codex_hooks = true in config.toml
    try ensureCodexConfigFlag()

    print("Codex: added hooks to \(codexSettingsPath)")
    print("Hook scripts installed to \(codexHooksDir)/")
}

private func uninstallCodexHooks() throws {
    // Back up existing settings before modifying
    try backupCodexSettings()

    // Remove hook entries from hooks.json
    try removeCodexHookEntries()

    // Remove hook scripts
    let fm = FileManager.default
    if fm.fileExists(atPath: codexHooksDir) {
        try fm.removeItem(atPath: codexHooksDir)
    }

    print("Codex: removed seshctl hooks from \(codexSettingsPath)")
}

private func installCodexHookScripts() throws {
    let fm = FileManager.default
    try fm.createDirectory(atPath: codexHooksDir, withIntermediateDirectories: true)

    let sourceHooksDir = findSourceCodexHooksDir()

    let scripts = ["session-start.sh", "user-prompt.sh", "stop.sh"]
    for script in scripts {
        let src = (sourceHooksDir as NSString).appendingPathComponent(script)
        let dst = (codexHooksDir as NSString).appendingPathComponent(script)

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

private func findSourceCodexHooksDir() -> String {
    let execDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
    let candidates = [
        (execDir as NSString).appendingPathComponent("../../hooks/codex"),
        (execDir as NSString).appendingPathComponent("../hooks/codex"),
        (execDir as NSString).appendingPathComponent("hooks/codex"),
        (execDir as NSString).appendingPathComponent("../../../hooks/codex"),
    ]

    let fm = FileManager.default
    for candidate in candidates {
        let resolved = (candidate as NSString).standardizingPath
        if fm.fileExists(atPath: resolved) {
            return resolved
        }
    }

    return (fm.currentDirectoryPath as NSString).appendingPathComponent("hooks/codex")
}

private func injectCodexHookEntries() throws {
    let fm = FileManager.default
    var settings: [String: Any] = [:]

    let settingsDir = (codexSettingsPath as NSString).deletingLastPathComponent
    try fm.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

    if fm.fileExists(atPath: codexSettingsPath) {
        let data = try Data(contentsOf: URL(fileURLWithPath: codexSettingsPath))
        settings =
            try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    var hooks = settings["hooks"] as? [String: Any] ?? [:]

    for entry in seshctlCodexHookEntries {
        var eventHooks = hooks[entry.event] as? [[String: Any]] ?? []

        let alreadyExists = eventHooks.contains { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshctl")
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
    try data.write(to: URL(fileURLWithPath: codexSettingsPath))
}

private func removeCodexHookEntries() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: codexSettingsPath) else { return }

    let data = try Data(contentsOf: URL(fileURLWithPath: codexSettingsPath))
    guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    guard var hooks = settings["hooks"] as? [String: Any] else { return }

    for entry in seshctlCodexHookEntries {
        guard var eventHooks = hooks[entry.event] as? [[String: Any]] else { continue }

        eventHooks.removeAll { group in
            guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
            return groupHooks.contains { hook in
                guard let cmd = hook["command"] as? String else { return false }
                return cmd.contains("seshctl")
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
    try updatedData.write(to: URL(fileURLWithPath: codexSettingsPath))
}

private func ensureCodexConfigFlag() throws {
    let fm = FileManager.default
    let configDir = (codexConfigPath as NSString).deletingLastPathComponent
    try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)

    if !fm.fileExists(atPath: codexConfigPath) {
        try "[features]\ncodex_hooks = true\n".write(
            toFile: codexConfigPath, atomically: true, encoding: .utf8
        )
        print("created \(codexConfigPath) with codex_hooks = true")
        return
    }

    let contents = try String(contentsOfFile: codexConfigPath, encoding: .utf8)

    if contents.contains("codex_hooks = true") {
        print("config.toml already has codex_hooks = true")
        return
    }

    var updated: String
    if contents.contains("[features]") {
        updated = contents.replacingOccurrences(
            of: "[features]",
            with: "[features]\ncodex_hooks = true"
        )
    } else {
        updated = contents + "\n[features]\ncodex_hooks = true\n"
    }

    try updated.write(toFile: codexConfigPath, atomically: true, encoding: .utf8)
    print("config.toml updated with codex_hooks = true")
}
