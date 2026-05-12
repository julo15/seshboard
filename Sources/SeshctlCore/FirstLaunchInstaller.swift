import Foundation

// MARK: - FirstLaunchInstaller

/// First-launch / on-demand installer for seshctl. Used by both the GUI app
/// (from `AppDelegate.applicationDidFinishLaunching` when the marker file is
/// missing) and the CLI (`seshctl-cli install`).
///
/// All operations are idempotent — running install twice is safe, running
/// uninstall against partial state is safe.
public enum FirstLaunchInstaller {

    // MARK: Result + error types

    public enum Action: Equatable {
        case symlinkCreated(String, target: String)
        case symlinkReplaced(String, target: String)
        case migratedRealFileToSymlink(String)
        case uninstallerScriptWritten(String)
        case hookScriptWritten(String)
        case hookRegistered(llm: String, event: String)
        case hookAlreadyRegistered(llm: String, event: String)
        case codexConfigUpdated
        case codexConfigAlreadySet
        case markerFileWritten(String)
        case removedHookEntry(llm: String, event: String)
        case removedSymlink(String)
        case removedFile(String)
        case removedDirectory(String)
        case noted(String)
    }

    public struct InstallResult {
        public let actions: [Action]
        public init(actions: [Action]) { self.actions = actions }
    }

    public struct UninstallResult {
        public let actions: [Action]
        public init(actions: [Action]) { self.actions = actions }
    }

    public enum InstallError: Error, CustomStringConvertible {
        case cliBinaryNotFound(searched: [String])
        case hookSourceNotFound(searched: [String])
        case ioError(String, underlying: Error)

        public var description: String {
            switch self {
            case .cliBinaryNotFound(let searched):
                return "Could not locate the seshctl-cli binary. Searched: \(searched.joined(separator: ", "))"
            case .hookSourceNotFound(let searched):
                return "Could not locate hook source scripts. Searched: \(searched.joined(separator: ", "))"
            case .ioError(let msg, let underlying):
                return "I/O error: \(msg) — \(underlying)"
            }
        }
    }

    // MARK: Public API

    /// True if the marker file exists at
    /// `~/Library/Application Support/Seshctl/installed-v1.json`.
    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: defaultPaths.markerFile)
    }

    /// Default `Paths` instance rooted at the current user's home directory.
    /// Production code uses this; tests inject a temp-rooted `Paths` instead.
    public static let defaultPaths = Paths()

    /// Full install: hooks + symlinks + uninstaller script + marker file.
    ///
    /// `bundleURL` is the .app bundle URL (e.g. `Bundle.main.bundleURL` when
    /// called from the GUI). Pass `nil` from CLI contexts where there's no
    /// bundle (a sensible fallback is used: `command -v seshctl-cli` on PATH,
    /// then `.build/release/seshctl-cli` relative to CWD).
    @discardableResult
    public static func install(bundleURL: URL?, paths: Paths = Paths()) throws -> InstallResult {
        var actions: [Action] = []

        // 1. Resolve CLI source path.
        let cliSource = try resolveCLISource(bundleURL: bundleURL)

        // 2. Symlinks in ~/.local/bin.
        try ensureDirectoryExists(atPath: paths.localBinDir, actions: &actions)
        try createOrReplaceSymlink(
            at: paths.seshctlSymlink, target: cliSource,
            allowMigrateRealFile: false, actions: &actions
        )
        try createOrReplaceSymlink(
            at: paths.seshctlCLISymlink, target: cliSource,
            allowMigrateRealFile: true, actions: &actions
        )

        // 3. Standalone uninstaller script.
        try writeUninstallerScript(paths: paths, actions: &actions)

        // 4. Hook scripts (with defensive guard prepended).
        let hookSourceDirs = try resolveHookSourceDirs(bundleURL: bundleURL)
        try writeHookScripts(
            sourceDir: hookSourceDirs.claude,
            destDir: paths.claudeHooksDir,
            scripts: HookSpec.claudeScriptNames,
            actions: &actions
        )
        try writeHookScripts(
            sourceDir: hookSourceDirs.codex,
            destDir: paths.codexHooksDir,
            scripts: HookSpec.codexScriptNames,
            actions: &actions
        )

        // 5. Register hooks in Claude Code settings.
        try injectHookEntries(
            settingsPath: paths.claudeSettingsFile,
            entries: HookSpec.claudeEntries(for: paths),
            llm: "claude",
            actions: &actions
        )

        // 6. Register hooks in Codex hooks.json.
        try injectHookEntries(
            settingsPath: paths.codexSettingsFile,
            entries: HookSpec.codexEntries(for: paths),
            llm: "codex",
            actions: &actions
        )

        // 7. Codex config flag.
        try ensureCodexConfigFlag(paths: paths, actions: &actions)

        // 8. Marker file.
        try writeMarkerFile(bundleURL: bundleURL, paths: paths, actions: &actions)

        return InstallResult(actions: actions)
    }

    /// Full uninstall — survives partial state.
    @discardableResult
    public static func uninstall(paths: Paths = Paths()) throws -> UninstallResult {
        var actions: [Action] = []

        // 1. Remove Claude Code hook entries.
        try removeHookEntries(
            settingsPath: paths.claudeSettingsFile,
            entries: HookSpec.claudeEntries(for: paths),
            llm: "claude",
            actions: &actions
        )

        // 2. Remove Codex hook entries.
        try removeHookEntries(
            settingsPath: paths.codexSettingsFile,
            entries: HookSpec.codexEntries(for: paths),
            llm: "codex",
            actions: &actions
        )

        // 3. Remove hook scripts directory.
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.hooksRoot) {
            try fm.removeItem(atPath: paths.hooksRoot)
            actions.append(.removedDirectory(paths.hooksRoot))
        }

        // 4. Remove symlinks (only if symlinks).
        for link in [paths.seshctlSymlink, paths.seshctlCLISymlink] {
            if isSymlink(atPath: link) {
                try fm.removeItem(atPath: link)
                actions.append(.removedSymlink(link))
            }
        }

        // 5. Remove standalone uninstaller.
        if fm.fileExists(atPath: paths.uninstallerScript) {
            try fm.removeItem(atPath: paths.uninstallerScript)
            actions.append(.removedFile(paths.uninstallerScript))
        }

        // 6. Remove application support directory (includes marker file).
        if fm.fileExists(atPath: paths.appSupportDir) {
            try fm.removeItem(atPath: paths.appSupportDir)
            actions.append(.removedDirectory(paths.appSupportDir))
        }

        // 7. Note: leave codex_hooks = true in ~/.agents/config.toml alone
        //    — other tools may rely on the flag.
        //    Note: leave ~/.local/share/seshctl/seshctl.db alone (user data).

        return UninstallResult(actions: actions)
    }

    // MARK: Paths

    /// Filesystem paths the installer touches. All paths are derived from
    /// `homeRoot`, which defaults to the current user's home directory but
    /// can be overridden in tests to point at a temp directory.
    public struct Paths: Sendable {
        public let homeRoot: URL

        public init(homeRoot: URL = FileManager.default.homeDirectoryForCurrentUser) {
            self.homeRoot = homeRoot
        }

        public var localBinDir: String {
            homeRoot.appendingPathComponent(".local/bin").path
        }
        public var seshctlSymlink: String {
            homeRoot.appendingPathComponent(".local/bin/seshctl").path
        }
        public var seshctlCLISymlink: String {
            homeRoot.appendingPathComponent(".local/bin/seshctl-cli").path
        }
        public var uninstallerScript: String {
            homeRoot.appendingPathComponent(".local/bin/seshctl-uninstall").path
        }

        public var hooksRoot: String {
            homeRoot.appendingPathComponent(".local/share/seshctl/hooks").path
        }
        public var claudeHooksDir: String {
            homeRoot.appendingPathComponent(".local/share/seshctl/hooks/claude").path
        }
        public var codexHooksDir: String {
            homeRoot.appendingPathComponent(".local/share/seshctl/hooks/codex").path
        }

        public var claudeSettingsFile: String {
            homeRoot.appendingPathComponent(".claude/settings.json").path
        }
        public var codexSettingsFile: String {
            homeRoot.appendingPathComponent(".agents/hooks.json").path
        }
        public var codexConfigFile: String {
            homeRoot.appendingPathComponent(".agents/config.toml").path
        }

        public var appSupportDir: String {
            homeRoot.appendingPathComponent("Library/Application Support/Seshctl").path
        }
        public var markerFile: String {
            homeRoot.appendingPathComponent("Library/Application Support/Seshctl/installed-v1.json").path
        }
    }

    // MARK: Hook spec

    enum HookSpec {
        static let claudeScriptNames = [
            "session-start.sh", "user-prompt.sh", "pre-tool-use.sh",
            "notification.sh", "stop.sh", "session-end.sh",
        ]
        static let codexScriptNames = ["session-start.sh", "user-prompt.sh", "stop.sh"]

        struct Entry {
            let event: String
            let matcher: String
            let command: String
        }

        static func claudeEntries(for paths: Paths) -> [Entry] {
            [
                .init(event: "SessionStart", matcher: "", command: "\(paths.claudeHooksDir)/session-start.sh"),
                .init(event: "UserPromptSubmit", matcher: "", command: "\(paths.claudeHooksDir)/user-prompt.sh"),
                .init(event: "PreToolUse", matcher: "", command: "\(paths.claudeHooksDir)/pre-tool-use.sh"),
                .init(event: "Notification", matcher: "", command: "\(paths.claudeHooksDir)/notification.sh"),
                .init(event: "Stop", matcher: "", command: "\(paths.claudeHooksDir)/stop.sh"),
                .init(event: "SessionEnd", matcher: "", command: "\(paths.claudeHooksDir)/session-end.sh"),
            ]
        }

        static func codexEntries(for paths: Paths) -> [Entry] {
            [
                .init(event: "SessionStart", matcher: "", command: "\(paths.codexHooksDir)/session-start.sh"),
                .init(event: "UserPromptSubmit", matcher: "", command: "\(paths.codexHooksDir)/user-prompt.sh"),
                .init(event: "Stop", matcher: "", command: "\(paths.codexHooksDir)/stop.sh"),
            ]
        }
    }

    // MARK: Step implementations

    static func resolveCLISource(bundleURL: URL?) throws -> String {
        let fm = FileManager.default

        if let bundleURL {
            let candidate = bundleURL
                .appendingPathComponent("Contents/MacOS/seshctl-cli")
                .path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            throw InstallError.cliBinaryNotFound(searched: [candidate])
        }

        // No bundle — try PATH then build/release.
        var searched: [String] = []
        if let onPath = which("seshctl-cli") {
            return onPath
        } else {
            searched.append("$PATH (command -v seshctl-cli)")
        }

        let cwd = fm.currentDirectoryPath
        let buildRelease = (cwd as NSString).appendingPathComponent(".build/release/seshctl-cli")
        searched.append(buildRelease)
        if fm.fileExists(atPath: buildRelease) {
            return buildRelease
        }

        throw InstallError.cliBinaryNotFound(searched: searched)
    }

    static func resolveHookSourceDirs(bundleURL: URL?) throws -> (claude: String, codex: String) {
        let fm = FileManager.default

        // Try the bundle first.
        if let bundleURL {
            let bundleClaude = bundleURL.appendingPathComponent("Contents/Resources/hooks/claude").path
            let bundleCodex = bundleURL.appendingPathComponent("Contents/Resources/hooks/codex").path
            if fm.fileExists(atPath: bundleClaude) && fm.fileExists(atPath: bundleCodex) {
                return (bundleClaude, bundleCodex)
            }
        }

        // Fall back to the repo source tree (the dev / `make install-cli` path).
        let execDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        let candidates: [String] = [
            (execDir as NSString).appendingPathComponent("../../hooks"),
            (execDir as NSString).appendingPathComponent("../hooks"),
            (execDir as NSString).appendingPathComponent("hooks"),
            (execDir as NSString).appendingPathComponent("../../../hooks"),
            (fm.currentDirectoryPath as NSString).appendingPathComponent("hooks"),
        ]

        for cand in candidates {
            let resolved = (cand as NSString).standardizingPath
            let claude = (resolved as NSString).appendingPathComponent("claude")
            let codex = (resolved as NSString).appendingPathComponent("codex")
            if fm.fileExists(atPath: claude) && fm.fileExists(atPath: codex) {
                return (claude, codex)
            }
        }

        throw InstallError.hookSourceNotFound(searched: candidates)
    }

    static func ensureDirectoryExists(atPath path: String, actions: inout [Action]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    static func createOrReplaceSymlink(
        at linkPath: String,
        target: String,
        allowMigrateRealFile: Bool,
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        let parent = (linkPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        // Inspect existing entry at linkPath.
        let attrs = try? fm.attributesOfItem(atPath: linkPath)
        let exists = attrs != nil
        let isLink = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink

        if exists {
            if isLink {
                // Read current destination — replace if different.
                let currentDest = try? fm.destinationOfSymbolicLink(atPath: linkPath)
                if currentDest == target {
                    return
                }
                try fm.removeItem(atPath: linkPath)
                try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
                actions.append(.symlinkReplaced(linkPath, target: target))
                return
            } else {
                // Real file at this path. Migration policy:
                //   - For seshctl-cli: this is the legacy `make install` artifact;
                //     replace it with our symlink and log the migration.
                //   - For seshctl: refuse to clobber. (User may have something
                //     unrelated there.)
                if allowMigrateRealFile {
                    try fm.removeItem(atPath: linkPath)
                    try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
                    actions.append(.migratedRealFileToSymlink(linkPath))
                    return
                } else {
                    // Replace anyway — the user's previous file at this path was
                    // ours (or interfering with us); align with the existing
                    // Install.swift behavior of overwriting hook scripts.
                    try fm.removeItem(atPath: linkPath)
                    try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
                    actions.append(.symlinkReplaced(linkPath, target: target))
                    return
                }
            }
        }

        try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
        actions.append(.symlinkCreated(linkPath, target: target))
    }

    static func writeUninstallerScript(paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        let parent = (paths.uninstallerScript as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        if fm.fileExists(atPath: paths.uninstallerScript) {
            try fm.removeItem(atPath: paths.uninstallerScript)
        }
        try uninstallerScriptContents.write(
            toFile: paths.uninstallerScript, atomically: true, encoding: .utf8
        )
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.uninstallerScript)
        actions.append(.uninstallerScriptWritten(paths.uninstallerScript))
    }

    static func writeHookScripts(
        sourceDir: String,
        destDir: String,
        scripts: [String],
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        for name in scripts {
            let src = (sourceDir as NSString).appendingPathComponent(name)
            let dst = (destDir as NSString).appendingPathComponent(name)

            guard fm.fileExists(atPath: src) else {
                throw InstallError.hookSourceNotFound(searched: [src])
            }

            let raw = try String(contentsOfFile: src, encoding: .utf8)
            let withGuard = injectHookGuard(into: raw)

            if fm.fileExists(atPath: dst) {
                try fm.removeItem(atPath: dst)
            }
            try withGuard.write(toFile: dst, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
            actions.append(.hookScriptWritten(dst))
        }
    }

    /// Insert the defensive guard block immediately after the `#!` shebang line.
    /// Idempotent — if the guard sentinel is already present, returns input
    /// unchanged.
    static func injectHookGuard(into script: String) -> String {
        if script.contains(hookGuardSentinel) {
            return script
        }

        // Split on first newline.
        guard let firstNewline = script.firstIndex(of: "\n") else {
            // No newline at all — script is just a single line. Append guard
            // after it.
            return script + "\n" + hookGuardBlock + "\n"
        }

        let firstLine = script[..<firstNewline]
        let rest = script[script.index(after: firstNewline)...]

        if firstLine.hasPrefix("#!") {
            return String(firstLine) + "\n" + hookGuardBlock + "\n" + String(rest)
        } else {
            // No shebang — prepend the guard block as the first content.
            return hookGuardBlock + "\n" + script
        }
    }

    static func injectHookEntries(
        settingsPath: String,
        entries: [HookSpec.Entry],
        llm: String,
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        let parent = (settingsPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            if !data.isEmpty {
                settings = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for entry in entries {
            var eventHooks = hooks[entry.event] as? [[String: Any]] ?? []

            let alreadyExists = eventHooks.contains { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains("seshctl")
                }
            }

            if alreadyExists {
                actions.append(.hookAlreadyRegistered(llm: llm, event: entry.event))
            } else {
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
                actions.append(.hookRegistered(llm: llm, event: entry.event))
            }

            hooks[entry.event] = eventHooks
        }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: settingsPath))
    }

    static func removeHookEntries(
        settingsPath: String,
        entries: [HookSpec.Entry],
        llm: String,
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else { return }

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        guard !data.isEmpty,
              var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for entry in entries {
            guard var eventHooks = hooks[entry.event] as? [[String: Any]] else { continue }

            let beforeCount = eventHooks.count
            eventHooks.removeAll { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains("seshctl")
                }
            }
            if eventHooks.count != beforeCount {
                actions.append(.removedHookEntry(llm: llm, event: entry.event))
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
        try updatedData.write(to: URL(fileURLWithPath: settingsPath))
    }

    static func ensureCodexConfigFlag(paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        let parent = (paths.codexConfigFile as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: paths.codexConfigFile) {
            try "[features]\ncodex_hooks = true\n".write(
                toFile: paths.codexConfigFile, atomically: true, encoding: .utf8
            )
            actions.append(.codexConfigUpdated)
            return
        }

        let contents = try String(contentsOfFile: paths.codexConfigFile, encoding: .utf8)
        if contents.contains("codex_hooks = true") {
            actions.append(.codexConfigAlreadySet)
            return
        }

        let updated: String
        if contents.contains("[features]") {
            updated = contents.replacingOccurrences(
                of: "[features]",
                with: "[features]\ncodex_hooks = true"
            )
        } else {
            updated = contents + "\n[features]\ncodex_hooks = true\n"
        }

        try updated.write(toFile: paths.codexConfigFile, atomically: true, encoding: .utf8)
        actions.append(.codexConfigUpdated)
    }

    static func writeMarkerFile(bundleURL: URL?, paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        let parent = (paths.markerFile as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        let bundlePath = bundleURL?.path ?? ""
        let version = readBundleVersion(bundleURL: bundleURL) ?? "dev"
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let payload: [String: Any] = [
            "bundlePath": bundlePath,
            "version": version,
            "installedAt": timestamp,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: paths.markerFile))
        actions.append(.markerFileWritten(paths.markerFile))
    }

    // MARK: Helpers

    static func isSymlink(atPath path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            return false
        }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", "command -v \(name) || true"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // command -v with our wrapper may return a shell builtin name; only
        // accept absolute paths to a real executable.
        guard trimmed.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: trimmed)
        else {
            return nil
        }
        return trimmed
    }

    static func readBundleVersion(bundleURL: URL?) -> String? {
        guard let bundleURL else { return nil }
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let obj = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ),
              let dict = obj as? [String: Any]
        else { return nil }
        return dict["CFBundleShortVersionString"] as? String
            ?? dict["CFBundleVersion"] as? String
    }
}

// MARK: - Embedded resources

extension FirstLaunchInstaller {
    /// Sentinel string that marks a hook script as having had the defensive
    /// guard block prepended. Used for idempotent re-injection.
    static let hookGuardSentinel = "# seshctl-defensive-guard-v1"

    /// Defensive guard prepended to every deployed hook script.
    ///
    /// If `seshctl-cli` isn't on PATH (bundle deleted), the hook no-ops. After
    /// 5 consecutive misses, it self-cleans by invoking `seshctl-uninstall`.
    /// If the binary IS on PATH the miss counter is reset.
    ///
    /// Note: this guard uses `rm -f` on its OWN tracking file — that's fine,
    /// the `trash` rule from AGENTS.md is for the assistant's actions, not for
    /// scripts deployed to user machines.
    static let hookGuardBlock = """
        \(hookGuardSentinel)
        if ! command -v seshctl-cli >/dev/null 2>&1; then
            SESHCTL_STATE="$HOME/Library/Application Support/Seshctl"
            MISS_FILE="$SESHCTL_STATE/hook-misses.json"
            mkdir -p "$SESHCTL_STATE" 2>/dev/null || true
            if command -v jq >/dev/null 2>&1 && [ -f "$MISS_FILE" ]; then
                misses=$(jq -r '.misses // 0' "$MISS_FILE" 2>/dev/null || echo 0)
            else
                misses=0
            fi
            misses=$((misses + 1))
            if command -v jq >/dev/null 2>&1; then
                printf '{"misses":%d,"lastMiss":"%s"}' "$misses" "$(date -u +%FT%TZ)" > "$MISS_FILE" 2>/dev/null || true
            fi
            if [ "$misses" -ge 5 ] && [ -x "$HOME/.local/bin/seshctl-uninstall" ]; then
                "$HOME/.local/bin/seshctl-uninstall" >/dev/null 2>&1 || true
            fi
            exit 0
        fi
        # Reset miss counter on success (binary present).
        rm -f "$HOME/Library/Application Support/Seshctl/hook-misses.json" 2>/dev/null || true
        """

    /// Verbatim contents of `scripts/seshctl-uninstall.sh`. Embedded as a
    /// Swift string so the bundle can drop it into `~/.local/bin/` without
    /// shipping the script as a separate resource.
    ///
    /// **Keep this in sync with `scripts/seshctl-uninstall.sh`** — there's a
    /// test in Step 6 (deferred) that compares the two byte-for-byte.
    static let uninstallerScriptContents: String = #"""
        #!/bin/bash
        # seshctl standalone uninstaller.
        #
        # This is a real file in ~/.local/bin/ (not a symlink into the bundle), so it
        # survives even if the user drags Seshctl.app to the Trash. It performs the
        # same cleanup as `FirstLaunchInstaller.uninstall()` but uses only `jq` + shell
        # so it has no dependency on the bundle being present.
        #
        # What gets removed:
        #   - seshctl-tagged hook entries from ~/.claude/settings.json
        #   - seshctl-tagged hook entries from ~/.agents/hooks.json
        #   - ~/.local/bin/seshctl, ~/.local/bin/seshctl-cli (only if symlinks)
        #   - ~/.local/bin/seshctl-uninstall (this file itself)
        #   - ~/.local/share/seshctl/hooks/  (NOT seshctl.db — that's user data)
        #   - ~/Library/Application Support/Seshctl/
        #
        # What this does NOT touch:
        #   - ~/.local/share/seshctl/seshctl.db (user data, kept like `make uninstall`)
        #   - ~/.agents/config.toml `codex_hooks` flag (other tools may rely on it)
        #   - /Applications/Seshctl.app (we'll log a reminder if it's still there)
        #
        # Idempotent: safe to run multiple times.

        set -euo pipefail

        CLAUDE_SETTINGS="$HOME/.claude/settings.json"
        CODEX_HOOKS="$HOME/.agents/hooks.json"
        HOOKS_DIR="$HOME/.local/share/seshctl/hooks"
        BIN_DIR="$HOME/.local/bin"
        SUPPORT_DIR="$HOME/Library/Application Support/Seshctl"
        APP_BUNDLE="/Applications/Seshctl.app"

        have_jq=1
        if ! command -v jq >/dev/null 2>&1; then
            have_jq=0
            echo "warning: jq not found — falling back to a less robust JSON cleanup." >&2
        fi

        # Strip seshctl-tagged hook entries from a Claude/Codex settings file.
        # A "seshctl-tagged" entry is one whose hooks[].command contains the substring
        # "seshctl" anywhere — same matcher used by the Swift installer.
        strip_seshctl_hooks() {
            local file="$1"
            [ -f "$file" ] || return 0

            if [ "$have_jq" -eq 1 ]; then
                local tmp
                tmp="$(mktemp)"
                if jq '
                    if .hooks then
                        .hooks |= with_entries(
                            .value |= map(select(
                                (.hooks // []) | map(.command // "") | map(test("seshctl")) | any | not
                            ))
                            | .value |= (if length == 0 then empty else . end)
                        )
                        | (if (.hooks | length) == 0 then del(.hooks) else . end)
                    else . end
                ' "$file" > "$tmp" 2>/dev/null; then
                    mv "$tmp" "$file"
                    echo "  cleaned $file"
                else
                    rm -f "$tmp"
                    echo "  warning: could not parse $file — left untouched" >&2
                fi
            else
                # Minimal fallback: just leave a backup and warn. We don't try to
                # hand-edit JSON without jq — too risky.
                cp "$file" "$file.seshctl-uninstall.bak"
                echo "  warning: leaving $file untouched (no jq); backup at $file.seshctl-uninstall.bak" >&2
            fi
        }

        echo "==> Removing seshctl hook entries from settings files"
        strip_seshctl_hooks "$CLAUDE_SETTINGS"
        strip_seshctl_hooks "$CODEX_HOOKS"

        echo "==> Removing CLI symlinks from $BIN_DIR"
        for link in "$BIN_DIR/seshctl" "$BIN_DIR/seshctl-cli"; do
            if [ -L "$link" ]; then
                rm -f "$link"
                echo "  removed symlink $link"
            elif [ -e "$link" ]; then
                echo "  skipping $link (real file, not a symlink — leaving it alone)"
            fi
        done

        echo "==> Removing hook scripts directory"
        if [ -d "$HOOKS_DIR" ]; then
            rm -rf "$HOOKS_DIR"
            echo "  removed $HOOKS_DIR"
        fi

        echo "==> Removing application support directory"
        if [ -d "$SUPPORT_DIR" ]; then
            rm -rf "$SUPPORT_DIR"
            echo "  removed $SUPPORT_DIR"
        fi

        if [ -e "$APP_BUNDLE" ]; then
            echo ""
            echo "Note: $APP_BUNDLE is still installed."
            echo "      Drag it to the Trash to complete the uninstall."
        fi

        # Self-delete last so the rest of the script always runs first.
        SELF="$BIN_DIR/seshctl-uninstall"
        if [ -f "$SELF" ]; then
            rm -f "$SELF"
        fi

        echo ""
        echo "seshctl uninstalled."
        """#
}
