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
        case codexConfigCleared(String)
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

    /// Decoded contents of the marker file written by `writeMarkerFile`.
    /// Matches the JSON keys produced there byte-for-byte
    /// (`bundlePath` / `version` / `installedAt`), so existing markers in the
    /// wild remain readable.
    ///
    /// `installedAt` is stored on disk as a `Double` (seconds since 1970),
    /// preserving sub-second precision so the `bundleNeedsRefresh` mtime
    /// comparison doesn't fire spuriously on every launch. For back-compat,
    /// `currentMarkerState(paths:)` also accepts a legacy ISO 8601 string
    /// representation (used by markers written before this change).
    public struct MarkerState: Equatable, Sendable {
        public let bundlePath: String
        public let version: String
        public let installedAt: Date

        public init(bundlePath: String, version: String, installedAt: Date) {
            self.bundlePath = bundlePath
            self.version = version
            self.installedAt = installedAt
        }
    }

    public struct UninstallResult {
        public let actions: [Action]
        public init(actions: [Action]) { self.actions = actions }
    }

    public enum InstallError: Error, CustomStringConvertible, LocalizedError {
        case cliBinaryNotFound(searched: [String])
        case hookSourceNotFound(searched: [String])
        case ioError(String, underlying: Error)
        case malformedSettings(path: String, backupPath: String)

        public var description: String {
            switch self {
            case .cliBinaryNotFound(let searched):
                return "Could not locate the seshctl-cli binary. Searched: \(searched.joined(separator: ", "))"
            case .hookSourceNotFound(let searched):
                return "Could not locate hook source scripts. Searched: \(searched.joined(separator: ", "))"
            case .ioError(let msg, let underlying):
                return "I/O error: \(msg) — \(underlying)"
            case .malformedSettings(let path, let backupPath):
                return "Refusing to overwrite malformed JSON at \(path). The original file has been backed up to \(backupPath). Fix or remove the file and re-run install."
            }
        }

        /// Surfaces `description` through Foundation's `localizedDescription`
        /// so the GUI error alert (which uses `error.localizedDescription`)
        /// renders the same human-readable message as the CLI.
        public var errorDescription: String? { description }
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

    /// Reads the marker file at `paths.markerFile` and returns its contents as
    /// a `MarkerState`. Returns `nil` if the file is missing or malformed.
    /// Does not throw — a missing/corrupt marker is just "no install record."
    public static func currentMarkerState(paths: Paths = Paths()) -> MarkerState? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.markerFile) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: paths.markerFile)),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let bundlePath = dict["bundlePath"] as? String,
              let version = dict["version"] as? String
        else {
            return nil
        }

        // `installedAt` is currently written as a `Double` (seconds since
        // 1970) to preserve sub-second precision. Legacy markers (written
        // before that change) stored it as an ISO 8601 string; accept both
        // shapes so old markers on user machines keep parsing.
        let installedAt: Date
        if let secs = dict["installedAt"] as? Double {
            installedAt = Date(timeIntervalSince1970: secs)
        } else if let installedAtStr = dict["installedAt"] as? String,
                  let parsed = ISO8601DateFormatter().date(from: installedAtStr) {
            installedAt = parsed
        } else {
            return nil
        }

        return MarkerState(
            bundlePath: bundlePath, version: version, installedAt: installedAt
        )
    }

    /// Returns `true` when the install marker exists but no longer matches the
    /// running bundle, signalling that AppDelegate should silently re-run
    /// `install(bundleURL:)` to refresh hooks / CLI symlinks / marker.
    ///
    /// Specifically returns `true` when any of the following hold:
    ///   - Marker's `bundlePath` differs from `bundleURL.path` (bundle moved)
    ///   - Marker's `version` differs from `currentVersion` (real release bump)
    ///   - The bundle's `Contents/MacOS/SeshctlApp` mtime is newer than the
    ///     marker's `installedAt` (dev iteration: `cp -R` of a fresh build
    ///     where the version string didn't change)
    ///
    /// Returns `false` when the marker is absent. The no-marker case is
    /// handled by the first-launch welcome panel path, which is gated on
    /// `isInstalled`; `bundleNeedsRefresh` is specifically for "marker exists
    /// but stale."
    public static func bundleNeedsRefresh(
        bundleURL: URL,
        currentVersion: String,
        paths: Paths = Paths()
    ) -> Bool {
        guard let marker = currentMarkerState(paths: paths) else {
            return false
        }
        if marker.bundlePath != bundleURL.path { return true }
        if marker.version != currentVersion { return true }

        let executablePath = bundleURL
            .appendingPathComponent("Contents/MacOS/SeshctlApp")
            .path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: executablePath),
           let execMtime = attrs[.modificationDate] as? Date,
           execMtime > marker.installedAt {
            return true
        }
        return false
    }

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
            paths: paths,
            actions: &actions
        )

        // 6. Register hooks in Codex hooks.json.
        try injectHookEntries(
            settingsPath: paths.codexSettingsFile,
            entries: HookSpec.codexEntries(for: paths),
            llm: "codex",
            paths: paths,
            actions: &actions
        )

        // 7. Codex config flag.
        try ensureCodexConfigFlag(paths: paths, actions: &actions)

        // 8. Marker file.
        try writeMarkerFile(bundleURL: bundleURL, paths: paths, actions: &actions)

        return InstallResult(actions: actions)
    }

    /// Full uninstall — survives partial state.
    ///
    /// Always removes:
    ///   - Claude Code + Codex hook registrations
    ///   - Hook scripts directory (`~/.local/share/seshctl/hooks/`)
    ///   - CLI symlinks (when they're symlinks)
    ///   - Standalone uninstaller script
    ///   - Application Support directory (includes marker)
    ///   - `codex_hooks = true` line in `~/.agents/config.toml` (and the
    ///     `[features]` header if it ends up empty)
    ///
    /// Conditionally removes when `deleteSessionHistory` is `true`:
    ///   - `~/.local/share/seshctl/seshctl.db` (plus any GRDB `-wal` / `-shm`
    ///     sidecars at the same prefix)
    ///   - `~/.local/share/seshctl/` itself, but ONLY if empty afterwards
    ///     (unrelated user files under that directory survive)
    @discardableResult
    public static func uninstall(
        paths: Paths = Paths(),
        deleteSessionHistory: Bool = false
    ) throws -> UninstallResult {
        var actions: [Action] = []

        // 1. Remove Claude Code hook entries.
        try removeHookEntries(
            settingsPath: paths.claudeSettingsFile,
            entries: HookSpec.claudeEntries(for: paths),
            llm: "claude",
            paths: paths,
            actions: &actions
        )

        // 2. Remove Codex hook entries.
        try removeHookEntries(
            settingsPath: paths.codexSettingsFile,
            entries: HookSpec.codexEntries(for: paths),
            llm: "codex",
            paths: paths,
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

        // 7. Always clear our codex feature flag — it's not user data, it
        //    only ever exists because we wrote it during install.
        try clearCodexConfigFlag(paths: paths, actions: &actions)

        // 8. Optionally remove the session history database (and its GRDB
        //    -wal / -shm sidecars). Off by default — see the CLI's
        //    --delete-history flag and the GUI's checkbox.
        if deleteSessionHistory {
            try removeSessionHistory(paths: paths, actions: &actions)
        }

        // 9. If ~/.local/share/seshctl/ is now empty (hooks removed +
        //    db removed if opted in + no unrelated sibling files), drop it.
        if fm.fileExists(atPath: paths.seshctlDataDir) {
            let contents = (try? fm.contentsOfDirectory(atPath: paths.seshctlDataDir)) ?? []
            if contents.isEmpty {
                try fm.removeItem(atPath: paths.seshctlDataDir)
                actions.append(.removedDirectory(paths.seshctlDataDir))
            }
        }

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

        public var seshctlDataDir: String {
            homeRoot.appendingPathComponent(".local/share/seshctl").path
        }
        public var sessionDB: String {
            homeRoot.appendingPathComponent(".local/share/seshctl/seshctl.db").path
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
        paths: Paths,
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        let parent = (settingsPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        // The prefix that identifies a hook command as one we deployed.
        // Anchoring here (instead of a bare "seshctl" substring) keeps us
        // from clobbering unrelated user-defined hooks that happen to have
        // "seshctl" anywhere in their command (e.g. a user's own fork at
        // ~/projects/seshctl-fork/foo.sh).
        let hookPrefix = (llm == "claude")
            ? paths.claudeHooksDir + "/"
            : paths.codexHooksDir + "/"

        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            if !data.isEmpty {
                do {
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        // Parsed OK but it's not a top-level dictionary
                        // (e.g. the file is a JSON array). Treat the same as
                        // malformed — we'd otherwise overwrite it.
                        throw NSError(domain: "FirstLaunchInstaller", code: 1, userInfo: nil)
                    }
                    settings = parsed
                } catch {
                    let backupPath = settingsPath + ".bak-\(Int(Date().timeIntervalSince1970))"
                    try? fm.copyItem(atPath: settingsPath, toPath: backupPath)
                    throw InstallError.malformedSettings(path: settingsPath, backupPath: backupPath)
                }
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for entry in entries {
            var eventHooks = hooks[entry.event] as? [[String: Any]] ?? []

            let alreadyExists = eventHooks.contains { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.hasPrefix(hookPrefix)
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
        paths: Paths,
        actions: inout [Action]
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else { return }

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        guard !data.isEmpty else { return }

        // Mirror injectHookEntries: malformed JSON should NOT be silently
        // ignored. If we can't parse the file, leave it alone and surface
        // an error with a backup pointer so the user can recover.
        var settings: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "FirstLaunchInstaller", code: 1, userInfo: nil)
            }
            settings = parsed
        } catch {
            let backupPath = settingsPath + ".bak-\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: settingsPath, toPath: backupPath)
            throw InstallError.malformedSettings(path: settingsPath, backupPath: backupPath)
        }

        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        // Same anchored-prefix matcher used by injectHookEntries — see the
        // comment there for the rationale. The matcher MUST match on a
        // path prefix (not a bare "seshctl" substring) so we don't strip
        // unrelated user hooks that happen to mention "seshctl".
        let hookPrefix = (llm == "claude")
            ? paths.claudeHooksDir + "/"
            : paths.codexHooksDir + "/"

        for entry in entries {
            guard var eventHooks = hooks[entry.event] as? [[String: Any]] else { continue }

            let beforeCount = eventHooks.count
            eventHooks.removeAll { group in
                guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.hasPrefix(hookPrefix)
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

    /// Mirror of `ensureCodexConfigFlag`, but for uninstall. Drops the
    /// `codex_hooks = true` line from `~/.agents/config.toml`. If the
    /// `[features]` section ends up with no keys, drops the header too.
    /// Other sections and keys are left untouched.
    ///
    /// Idempotent: missing file or missing line → no-op.
    static func clearCodexConfigFlag(paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.codexConfigFile) else { return }

        let original = try String(contentsOfFile: paths.codexConfigFile, encoding: .utf8)
        guard original.contains("codex_hooks = true") else { return }

        // Walk the file line-by-line, tracking which section we're in. Drop
        // the `codex_hooks = true` line whenever we see it. After the pass,
        // also drop the `[features]` header if that section is empty.
        //
        // A "section" runs from a `[name]` header up to the next header (or
        // EOF). Lines between are either key/value pairs, blanks, or
        // comments. We consider the section "empty" if it has no non-blank,
        // non-comment key lines after the drop.
        struct Section {
            var header: String?         // e.g. "[features]" or nil for the preamble
            var lines: [String] = []    // body lines (NOT including the header itself)
        }

        var sections: [Section] = [Section()]
        let rawLines = original.components(separatedBy: "\n")
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                sections.append(Section(header: line))
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }

        // Drop the codex_hooks line from any section that contains it
        // (defensive — really should only ever be in [features]).
        for i in sections.indices {
            sections[i].lines.removeAll { line in
                line.trimmingCharacters(in: .whitespaces) == "codex_hooks = true"
            }
        }

        // If [features] is now empty, drop the whole section (header + body).
        // "Empty" means: no non-blank, non-comment lines remain.
        sections.removeAll { section in
            guard let header = section.header else { return false }
            guard header.trimmingCharacters(in: .whitespaces) == "[features]" else { return false }
            let hasRealContent = section.lines.contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#")
            }
            return !hasRealContent
        }

        // Rebuild the file.
        var rebuilt: [String] = []
        for section in sections {
            if let header = section.header { rebuilt.append(header) }
            rebuilt.append(contentsOf: section.lines)
        }
        var output = rebuilt.joined(separator: "\n")

        // Collapse runs of 3+ blank lines down to 2 — keeps things tidy when
        // an entire section is removed mid-file. Don't go aggressive on
        // single-blank cleanup; users may have intentional spacing.
        while output.contains("\n\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n\n", with: "\n\n\n")
        }

        try output.write(toFile: paths.codexConfigFile, atomically: true, encoding: .utf8)
        actions.append(.codexConfigCleared(paths.codexConfigFile))
    }

    /// Remove `~/.local/share/seshctl/seshctl.db` plus any GRDB `-wal` /
    /// `-shm` sidecar files at the same prefix. Idempotent.
    static func removeSessionHistory(paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        let dir = paths.seshctlDataDir
        guard fm.fileExists(atPath: dir) else { return }

        let dbName = (paths.sessionDB as NSString).lastPathComponent  // "seshctl.db"
        // Only delete the main DB file and GRDB's own sidecars. Anything else
        // sharing the `seshctl.db` prefix (e.g. a user's `seshctl.db-backup`)
        // is left alone.
        let targets: Set<String> = [
            dbName,
            "\(dbName)-wal",
            "\(dbName)-shm",
            "\(dbName)-journal",
        ]
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        for entry in entries {
            guard targets.contains(entry) else { continue }
            let full = (dir as NSString).appendingPathComponent(entry)
            try fm.removeItem(atPath: full)
            actions.append(.removedFile(full))
        }
    }

    static func writeMarkerFile(bundleURL: URL?, paths: Paths, actions: inout [Action]) throws {
        let fm = FileManager.default
        let parent = (paths.markerFile as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)

        let bundlePath = bundleURL?.path ?? ""
        let version = readBundleVersion(bundleURL: bundleURL) ?? "dev"

        // Store `installedAt` as a `Double` (seconds since 1970). The
        // previous ISO 8601 string had 1 s precision, which made
        // `bundleNeedsRefresh` fire on every launch because file mtimes
        // carry sub-second precision and would read "newer" than the
        // marker's `installedAt`. `currentMarkerState` still accepts the
        // legacy string form for back-compat.
        let installedAt = Date().timeIntervalSince1970

        let payload: [String: Any] = [
            "bundlePath": bundlePath,
            "version": version,
            "installedAt": installedAt,
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
    /// parity test in `FirstLaunchInstallerTests` that compares the two
    /// byte-for-byte. Any change must be applied to both copies.
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
        #   - codex_hooks = true line in ~/.agents/config.toml (and [features] if empty)
        #
        # What this does NOT touch:
        #   - ~/.local/share/seshctl/seshctl.db (user data, kept like `make uninstall`)
        #   - /Applications/Seshctl.app (we'll log a reminder if it's still there)
        #
        # Idempotent: safe to run multiple times.

        set -euo pipefail

        CLAUDE_SETTINGS="$HOME/.claude/settings.json"
        CODEX_HOOKS="$HOME/.agents/hooks.json"
        HOOKS_DIR="$HOME/.local/share/seshctl/hooks"
        HOOK_PREFIX="$HOME/.local/share/seshctl/hooks/"
        BIN_DIR="$HOME/.local/bin"
        SUPPORT_DIR="$HOME/Library/Application Support/Seshctl"
        APP_BUNDLE="/Applications/Seshctl.app"
        CODEX_CONFIG="$HOME/.agents/config.toml"

        have_jq=1
        if ! command -v jq >/dev/null 2>&1; then
            have_jq=0
            echo "warning: jq not found — falling back to a less robust JSON cleanup." >&2
        fi

        # Strip seshctl-tagged hook entries from a Claude/Codex settings file.
        # A "seshctl-tagged" entry is one whose hooks[].command starts with the
        # deployed hooks dir prefix (~/.local/share/seshctl/hooks/) — same anchored
        # matcher used by the Swift installer. Anchoring keeps us from stripping
        # user-defined hooks that mention "seshctl" elsewhere in their command.
        strip_seshctl_hooks() {
            local file="$1"
            [ -f "$file" ] || return 0

            if [ "$have_jq" -eq 1 ]; then
                local tmp
                tmp="$(mktemp)"
                if jq --arg prefix "$HOOK_PREFIX" '
                    if .hooks then
                        .hooks |= with_entries(
                            .value |= map(select(
                                (.hooks // []) | map(.command // "") | map(startswith($prefix)) | any | not
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

        echo "==> Clearing codex_hooks flag from $CODEX_CONFIG"
        if [ -f "$CODEX_CONFIG" ]; then
            if grep -q '^codex_hooks = true$' "$CODEX_CONFIG"; then
                # Drop the flag line.
                sed -i '' '/^codex_hooks = true$/d' "$CODEX_CONFIG"
                # If [features] is now empty (no key/value lines between it and the next
                # header or EOF), drop the header line too. This mirrors the Swift
                # clearCodexConfigFlag — install only writes [features] / codex_hooks
                # when we put it there, so cleaning it up is part of "leave no trace."
                awk '
                    BEGIN { features=0; buf="" }
                    /^\[features\][[:space:]]*$/ {
                        features=1; buf=$0; next
                    }
                    features==1 {
                        if ($0 ~ /^\[/) {
                            # Hit the next section header. [features] is empty —
                            # drop the saved header line and continue.
                            features=0
                            print
                            next
                        }
                        if ($0 ~ /^[[:space:]]*$/) {
                            # Blank line inside [features] — buffer it; we still
                            # might find a non-blank key below.
                            buf = buf "\n" $0
                            next
                        }
                        # Any non-blank, non-header line = [features] is non-empty.
                        # Flush the buffered header (and any blanks) and print this
                        # line as well.
                        print buf
                        print $0
                        features=0
                        next
                    }
                    features==0 { print }
                    END {
                        # If we hit EOF while still inside an empty [features], drop
                        # the buffered header. Otherwise we already flushed it.
                    }
                ' "$CODEX_CONFIG" > "$CODEX_CONFIG.tmp" && mv "$CODEX_CONFIG.tmp" "$CODEX_CONFIG"
                echo "  cleared codex_hooks = true from $CODEX_CONFIG"
            fi
        fi

        echo "==> Removing application support directory"
        if [ -d "$SUPPORT_DIR" ]; then
            rm -rf "$SUPPORT_DIR"
            echo "  removed $SUPPORT_DIR"
        fi

        for candidate in "/Applications/Seshctl.app" "$HOME/Applications/Seshctl.app" "$HOME/Downloads/Seshctl.app"; do
            if [ -d "$candidate" ]; then
                echo "Seshctl.app is still installed at $candidate — drag it to Trash to complete uninstall."
                break
            fi
        done

        # Self-delete last so the rest of the script always runs first.
        SELF="$BIN_DIR/seshctl-uninstall"
        if [ -f "$SELF" ]; then
            rm -f "$SELF"
        fi

        echo ""
        echo "seshctl uninstalled."

        """#
}
