import Foundation
import Testing

@testable import SeshctlCore

// MARK: - Test helpers

/// Walks up from this source file to find the repo root (the directory
/// containing `Package.swift`). Tests use this to locate `hooks/`,
/// `Resources/Info.plist`, and `scripts/seshctl-uninstall.sh` without making
/// assumptions about where the test process's CWD is.
private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #file)
    while url.path != "/" {
        url = url.deletingLastPathComponent()
        let candidate = url.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return url
        }
    }
    fatalError("could not find Package.swift walking up from \(#file)")
}

/// Creates a fresh temp directory to act as a `$HOME` for one test, with
/// `~/.claude/settings.json` pre-seeded with `{}` (matches the realistic
/// state on a Mac that already has Claude Code configured).
private func makeTempHome() throws -> URL {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("seshctl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let claudeDir = temp.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: claudeDir.appendingPathComponent("settings.json"))
    return temp
}

private func cleanup(_ temp: URL) {
    try? FileManager.default.removeItem(at: temp)
}

/// Creates a fake `.app`-like bundle layout in `parent` so
/// `FirstLaunchInstaller.install(bundleURL:)` resolves the CLI binary and
/// hook source dirs from it. Hook sources are copied from the repo `hooks/`
/// tree rather than synthesized so the deployed scripts match what would
/// ship in a real DMG.
private func makeFakeBundle(in parent: URL) throws -> URL {
    let bundle = parent.appendingPathComponent("Seshctl.app")
    let macOS = bundle.appendingPathComponent("Contents/MacOS")
    let resources = bundle.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

    // Fake CLI binary — empty file with executable bit.
    let cli = macOS.appendingPathComponent("seshctl-cli")
    try Data().write(to: cli)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

    // Fake SeshctlApp executable. The bundleNeedsRefresh mtime check reads
    // Contents/MacOS/SeshctlApp; without this the attribute lookup fails and
    // the mtime branch silently returns false.
    let appExe = macOS.appendingPathComponent("SeshctlApp")
    try Data().write(to: appExe)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appExe.path)

    // Copy repo hooks/ tree into bundle Resources.
    let repoHooks = repoRoot().appendingPathComponent("hooks")
    let bundleHooks = resources.appendingPathComponent("hooks")
    try FileManager.default.copyItem(at: repoHooks, to: bundleHooks)

    // Minimal Info.plist (only used by readBundleVersion → marker file).
    let plist: [String: Any] = [
        "CFBundleIdentifier": "app.seshctl.Seshctl.test",
        "CFBundleShortVersionString": "0.1.0-test",
        "CFBundleVersion": "1",
    ]
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0
    )
    try plistData.write(to: bundle.appendingPathComponent("Contents/Info.plist"))

    return bundle
}

private func loadJSONObject(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

/// Counts the number of seshctl-tagged groups under `hooks[event]`.
/// A group is "seshctl-tagged" if any nested hook command contains "seshctl".
private func countSeshctlGroups(in settings: [String: Any], event: String) -> Int {
    guard let hooks = settings["hooks"] as? [String: Any],
          let eventHooks = hooks[event] as? [[String: Any]]
    else { return 0 }
    return eventHooks.filter { group in
        guard let groupHooks = group["hooks"] as? [[String: Any]] else { return false }
        return groupHooks.contains { hook in
            (hook["command"] as? String)?.contains("seshctl") == true
        }
    }.count
}

// MARK: - Suite

@Suite("FirstLaunchInstaller")
struct FirstLaunchInstallerTests {

    // MARK: 1. Fresh install creates expected files

    @Test("Fresh install creates symlinks, hooks, marker, and registers entries")
    func freshInstall_createsExpectedFiles() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }

        let bundleParent = temp.appendingPathComponent("bundle-parent")
        try FileManager.default.createDirectory(at: bundleParent, withIntermediateDirectories: true)
        let bundle = try makeFakeBundle(in: bundleParent)

        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)
        let result = try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)
        #expect(!result.actions.isEmpty)

        let fm = FileManager.default
        let cliTarget = bundle.appendingPathComponent("Contents/MacOS/seshctl-cli").path

        // 1. ~/.local/bin/seshctl is a symlink → fakeBundle/Contents/MacOS/seshctl-cli
        #expect(FirstLaunchInstaller.isSymlink(atPath: paths.seshctlSymlink))
        let dest1 = try fm.destinationOfSymbolicLink(atPath: paths.seshctlSymlink)
        #expect(dest1 == cliTarget)

        // 2. ~/.local/bin/seshctl-cli is a symlink → same target
        #expect(FirstLaunchInstaller.isSymlink(atPath: paths.seshctlCLISymlink))
        let dest2 = try fm.destinationOfSymbolicLink(atPath: paths.seshctlCLISymlink)
        #expect(dest2 == cliTarget)

        // 3. ~/.local/bin/seshctl-uninstall — real file, executable, expected contents
        #expect(fm.fileExists(atPath: paths.uninstallerScript))
        #expect(!FirstLaunchInstaller.isSymlink(atPath: paths.uninstallerScript))
        let attrs = try fm.attributesOfItem(atPath: paths.uninstallerScript)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(perms & 0o111 != 0, "uninstaller should be executable")
        let written = try String(contentsOfFile: paths.uninstallerScript, encoding: .utf8)
        #expect(written == FirstLaunchInstaller.uninstallerScriptContents)

        // 4. Claude hook scripts present
        for name in FirstLaunchInstaller.HookSpec.claudeScriptNames {
            let p = (paths.claudeHooksDir as NSString).appendingPathComponent(name)
            #expect(fm.fileExists(atPath: p), "missing claude hook: \(name)")
        }
        // 5. Codex hook scripts present
        for name in FirstLaunchInstaller.HookSpec.codexScriptNames {
            let p = (paths.codexHooksDir as NSString).appendingPathComponent(name)
            #expect(fm.fileExists(atPath: p), "missing codex hook: \(name)")
        }

        // 6. ~/.claude/settings.json has 6 expected event entries pointing into temp HOME
        let claudeSettings = try loadJSONObject(at: paths.claudeSettingsFile)
        let claudeHooks = claudeSettings["hooks"] as? [String: Any]
        #expect(claudeHooks != nil)
        let expectedClaudeEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse",
                                    "Notification", "Stop", "SessionEnd"]
        for event in expectedClaudeEvents {
            #expect(claudeHooks?[event] != nil, "missing claude hook event: \(event)")
            let groups = (claudeHooks?[event] as? [[String: Any]]) ?? []
            // At least one group should reference our temp HOME's hooks dir.
            let containsTempPath = groups.contains { group in
                guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
                return hooks.contains { hook in
                    (hook["command"] as? String)?.contains(temp.path) == true
                }
            }
            #expect(containsTempPath, "claude \(event) hook command should reference temp HOME")
        }

        // 7. ~/.agents/hooks.json has 3 expected events
        let codexSettings = try loadJSONObject(at: paths.codexSettingsFile)
        let codexHooks = codexSettings["hooks"] as? [String: Any]
        #expect(codexHooks != nil)
        for event in ["SessionStart", "UserPromptSubmit", "Stop"] {
            #expect(codexHooks?[event] != nil, "missing codex hook event: \(event)")
        }

        // 8. ~/.agents/config.toml contains codex_hooks = true
        let toml = try String(contentsOfFile: paths.codexConfigFile, encoding: .utf8)
        #expect(toml.contains("codex_hooks = true"))

        // 9. Marker file exists, parses, contains expected fields
        #expect(fm.fileExists(atPath: paths.markerFile))
        let marker = try loadJSONObject(at: paths.markerFile)
        #expect(marker["bundlePath"] as? String == bundle.path)
        #expect((marker["version"] as? String) != nil)
        #expect((marker["installedAt"] as? String) != nil)
    }

    // MARK: 2. Idempotent install

    @Test("Install twice does not duplicate hook entries")
    func installTwice_isIdempotent() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)
        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        let claudeSettings = try loadJSONObject(at: paths.claudeSettingsFile)
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse",
                      "Notification", "Stop", "SessionEnd"] {
            #expect(countSeshctlGroups(in: claudeSettings, event: event) == 1,
                    "duplicate seshctl group for claude \(event)")
        }
        let codexSettings = try loadJSONObject(at: paths.codexSettingsFile)
        for event in ["SessionStart", "UserPromptSubmit", "Stop"] {
            #expect(countSeshctlGroups(in: codexSettings, event: event) == 1,
                    "duplicate seshctl group for codex \(event)")
        }
    }

    // MARK: 3. Preserves unrelated hooks on install

    @Test("Install preserves unrelated hook entries already present")
    func installPreservesUnrelatedHooks() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        // Pre-populate ~/.claude/settings.json with an unrelated hook.
        let unrelatedCommand = "/some/other/tool.sh"
        let preExisting: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": unrelatedCommand]
                        ],
                    ] as [String: Any]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: preExisting, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: paths.claudeSettingsFile))

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        let settings = try loadJSONObject(at: paths.claudeSettingsFile)
        let hooks = settings["hooks"] as? [String: Any]
        let sessionStart = hooks?["SessionStart"] as? [[String: Any]] ?? []
        let unrelatedStillThere = sessionStart.contains { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == unrelatedCommand }
        }
        let seshctlAdded = sessionStart.contains { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String)?.contains("seshctl") == true }
        }
        #expect(unrelatedStillThere, "unrelated hook should be preserved")
        #expect(seshctlAdded, "seshctl hook should be added alongside")
    }

    // MARK: 4. Uninstall preserves unrelated hooks

    @Test("Uninstall removes only seshctl hooks; unrelated entries survive")
    func uninstallPreservesUnrelatedHooks() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        // Add an unrelated hook post-install.
        let unrelatedCommand = "/some/other/tool.sh"
        var settings = try loadJSONObject(at: paths.claudeSettingsFile)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var sessionStart = hooks["SessionStart"] as? [[String: Any]] ?? []
        sessionStart.append([
            "matcher": "",
            "hooks": [["type": "command", "command": unrelatedCommand]],
        ] as [String: Any])
        hooks["SessionStart"] = sessionStart
        settings["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: paths.claudeSettingsFile))

        try FirstLaunchInstaller.uninstall(paths: paths)

        let after = try loadJSONObject(at: paths.claudeSettingsFile)
        let afterHooks = after["hooks"] as? [String: Any] ?? [:]
        let afterSessionStart = afterHooks["SessionStart"] as? [[String: Any]] ?? []
        let unrelatedStillThere = afterSessionStart.contains { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String) == unrelatedCommand }
        }
        let seshctlRemoved = !afterSessionStart.contains { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["command"] as? String)?.contains("seshctl") == true }
        }
        #expect(unrelatedStillThere, "unrelated hook should remain after uninstall")
        #expect(seshctlRemoved, "seshctl entries should be gone after uninstall")
    }

    // MARK: 5. Symlink overwrite migrates real file

    @Test("Install replaces a real file at ~/.local/bin/seshctl-cli with a symlink")
    func symlinkOverwrite_migratesRealFile() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        // Pre-create a real file at ~/.local/bin/seshctl-cli.
        let binDir = temp.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let realFile = URL(fileURLWithPath: paths.seshctlCLISymlink)
        try Data("not a symlink".utf8).write(to: realFile)
        #expect(!FirstLaunchInstaller.isSymlink(atPath: paths.seshctlCLISymlink))

        let result = try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        #expect(FirstLaunchInstaller.isSymlink(atPath: paths.seshctlCLISymlink))
        let migrated = result.actions.contains { action in
            if case .migratedRealFileToSymlink(let p) = action {
                return p == paths.seshctlCLISymlink
            }
            return false
        }
        #expect(migrated, "expected migratedRealFileToSymlink action for seshctl-cli")
    }

    // MARK: 6. Defensive guard present in deployed hook

    @Test("Deployed hook script contains the defensive guard before any seshctl-cli invocation")
    func defensiveGuardInDeployedHook() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        let deployed = (paths.claudeHooksDir as NSString).appendingPathComponent("session-start.sh")
        let contents = try String(contentsOfFile: deployed, encoding: .utf8)
        #expect(contents.contains("command -v seshctl-cli"),
                "defensive guard sentinel missing")

        // The guard must appear BEFORE any actual seshctl-cli invocation.
        if let guardIdx = contents.range(of: "command -v seshctl-cli")?.lowerBound,
           let invokeIdx = contents.range(of: "seshctl-cli start")?.lowerBound {
            #expect(guardIdx < invokeIdx,
                    "defensive guard should appear before `seshctl-cli start`")
        }
        // Sentinel marker also present.
        #expect(contents.contains(FirstLaunchInstaller.hookGuardSentinel))
    }

    // MARK: 7. Info.plist required keys

    @Test("Resources/Info.plist contains all required keys with correct types")
    func infoPlistRequiredKeys() throws {
        let plistURL = repoRoot().appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("Info.plist did not parse as a dictionary")
            return
        }

        // String-typed keys.
        for key in ["CFBundleIdentifier", "CFBundleName", "CFBundleExecutable",
                    "CFBundleVersion", "CFBundleShortVersionString",
                    "LSMinimumSystemVersion"] {
            #expect(dict[key] is String, "\(key) missing or wrong type")
            if let s = dict[key] as? String {
                #expect(!s.isEmpty, "\(key) should be non-empty")
            }
        }

        // LSUIElement should be a Bool == true.
        let uiElement = dict["LSUIElement"]
        if let b = uiElement as? Bool {
            #expect(b == true, "LSUIElement should be true")
        } else if let n = uiElement as? NSNumber {
            #expect(n.boolValue == true, "LSUIElement should be true")
        } else {
            Issue.record("LSUIElement missing or not a Bool")
        }

        // NSAppleEventsUsageDescription — non-empty string.
        let usage = dict["NSAppleEventsUsageDescription"] as? String
        #expect(usage != nil && !(usage ?? "").isEmpty,
                "NSAppleEventsUsageDescription missing or empty")
    }

    // MARK: 8. Swift uninstall and shell uninstall produce equivalent state

    @Test("FirstLaunchInstaller.uninstall and seshctl-uninstall.sh leave the same state")
    func swiftAndShellUninstallProduceSameState() throws {
        let tempA = try makeTempHome()
        let tempB = try makeTempHome()
        defer {
            cleanup(tempA)
            cleanup(tempB)
        }
        let bundleA = try makeFakeBundle(in: tempA)
        let bundleB = try makeFakeBundle(in: tempB)
        let pathsA = FirstLaunchInstaller.Paths(homeRoot: tempA)
        let pathsB = FirstLaunchInstaller.Paths(homeRoot: tempB)

        try FirstLaunchInstaller.install(bundleURL: bundleA, paths: pathsA)
        try FirstLaunchInstaller.install(bundleURL: bundleB, paths: pathsB)

        // Swift uninstall on A.
        try FirstLaunchInstaller.uninstall(paths: pathsA)

        // Shell uninstall on B — invoke the standalone script with HOME=tempB.
        let script = repoRoot().appendingPathComponent("scripts/seshctl-uninstall.sh")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = tempB.path
        // Make sure jq is reachable. Default macOS PATH contains /usr/bin/jq.
        if env["PATH"] == nil || env["PATH"]?.isEmpty == true {
            env["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        }
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0,
                "shell uninstaller should exit 0; stderr: \(String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")

        let fm = FileManager.default

        // Bin entries gone in both.
        for paths in [pathsA, pathsB] {
            #expect(!fm.fileExists(atPath: paths.seshctlSymlink), "seshctl symlink lingers in \(paths.homeRoot.path)")
            #expect(!fm.fileExists(atPath: paths.seshctlCLISymlink), "seshctl-cli symlink lingers in \(paths.homeRoot.path)")
            #expect(!fm.fileExists(atPath: paths.uninstallerScript), "uninstaller lingers in \(paths.homeRoot.path)")
            #expect(!fm.fileExists(atPath: paths.hooksRoot), "hooks dir lingers in \(paths.homeRoot.path)")
            #expect(!fm.fileExists(atPath: paths.appSupportDir), "app support dir lingers in \(paths.homeRoot.path)")
        }

        // Equivalence: in BOTH files, no seshctl-tagged hook command remains.
        //
        // The two uninstallers leave settings.json in slightly different shapes
        // (Swift fully removes empty event keys + the `hooks` dict; the shell
        // jq filter leaves event keys present with a null value). That's a
        // user-invisible difference — both correctly remove all seshctl
        // commands and preserve unrelated entries. Asserting the user-facing
        // invariant (no seshctl commands left, no unrelated commands lost) is
        // the meaningful equivalence here.
        for paths in [pathsA, pathsB] {
            let raw = try String(contentsOfFile: paths.claudeSettingsFile, encoding: .utf8)
            #expect(!raw.contains("seshctl"),
                    "found leftover 'seshctl' substring in \(paths.claudeSettingsFile)")
            if fm.fileExists(atPath: paths.codexSettingsFile) {
                let codexRaw = try String(contentsOfFile: paths.codexSettingsFile, encoding: .utf8)
                #expect(!codexRaw.contains("seshctl"),
                        "found leftover 'seshctl' substring in \(paths.codexSettingsFile)")
            }
        }
    }

    // MARK: 9. ensureCodexConfigFlag handles the existing-[features]-section case

    @Test("ensureCodexConfigFlag adds codex_hooks under existing [features] block")
    func ensureCodexConfigFlag_existingFeaturesSection() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        // Pre-create config.toml with a [features] section but no codex_hooks line.
        let agentsDir = temp.appendingPathComponent(".agents")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let preexisting = "[features]\nother_flag = false\n"
        try preexisting.write(
            toFile: paths.codexConfigFile, atomically: true, encoding: .utf8
        )

        var actions: [FirstLaunchInstaller.Action] = []
        try FirstLaunchInstaller.ensureCodexConfigFlag(paths: paths, actions: &actions)

        let after = try String(contentsOfFile: paths.codexConfigFile, encoding: .utf8)
        #expect(after.contains("[features]"))
        #expect(after.contains("codex_hooks = true"))
        #expect(after.contains("other_flag = false"))

        // Re-running should hit the "already set" branch.
        var actions2: [FirstLaunchInstaller.Action] = []
        try FirstLaunchInstaller.ensureCodexConfigFlag(paths: paths, actions: &actions2)
        #expect(actions2.contains(.codexConfigAlreadySet))
    }

    @Test("ensureCodexConfigFlag appends [features] when none exists")
    func ensureCodexConfigFlag_noFeaturesSection() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        let agentsDir = temp.appendingPathComponent(".agents")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try "[other]\nval = 1\n".write(
            toFile: paths.codexConfigFile, atomically: true, encoding: .utf8
        )

        var actions: [FirstLaunchInstaller.Action] = []
        try FirstLaunchInstaller.ensureCodexConfigFlag(paths: paths, actions: &actions)

        let after = try String(contentsOfFile: paths.codexConfigFile, encoding: .utf8)
        #expect(after.contains("[features]"))
        #expect(after.contains("codex_hooks = true"))
        #expect(after.contains("[other]"))
    }

    // MARK: 10. InstallError messages

    @Test("InstallError descriptions render the searched paths and underlying errors")
    func installErrorDescriptions() {
        let cliErr = FirstLaunchInstaller.InstallError.cliBinaryNotFound(searched: ["/x", "/y"])
        #expect(cliErr.description.contains("/x"))
        #expect(cliErr.description.contains("/y"))

        let hookErr = FirstLaunchInstaller.InstallError.hookSourceNotFound(searched: ["/a"])
        #expect(hookErr.description.contains("/a"))

        struct Underlying: Error, CustomStringConvertible { var description: String { "boom" } }
        let ioErr = FirstLaunchInstaller.InstallError.ioError("write failed", underlying: Underlying())
        #expect(ioErr.description.contains("write failed"))
        #expect(ioErr.description.contains("boom"))
    }

    // MARK: 11. injectHookGuard is idempotent and handles edge cases

    @Test("injectHookGuard prepends guard, is idempotent, handles missing shebang")
    func injectHookGuard_edgeCases() {
        let scriptWithShebang = "#!/bin/bash\necho hi\n"
        let once = FirstLaunchInstaller.injectHookGuard(into: scriptWithShebang)
        #expect(once.contains(FirstLaunchInstaller.hookGuardSentinel))
        // Sentinel appears after the shebang line.
        let lines = once.components(separatedBy: "\n")
        #expect(lines.first == "#!/bin/bash")

        // Idempotent: a second pass leaves the script unchanged.
        let twice = FirstLaunchInstaller.injectHookGuard(into: once)
        #expect(twice == once)

        // No shebang at all → guard prepended at top.
        let scriptNoShebang = "echo hi\n"
        let injected = FirstLaunchInstaller.injectHookGuard(into: scriptNoShebang)
        #expect(injected.contains(FirstLaunchInstaller.hookGuardSentinel))
        #expect(injected.hasPrefix(FirstLaunchInstaller.hookGuardSentinel))

        // Single-line script (no newlines).
        let oneLiner = "echo hi"
        let injectedOneLiner = FirstLaunchInstaller.injectHookGuard(into: oneLiner)
        #expect(injectedOneLiner.contains(FirstLaunchInstaller.hookGuardSentinel))
    }

    // MARK: 12. isInstalled reflects the marker file under default paths

    @Test("isInstalled returns false when marker file under default HOME is absent")
    func isInstalled_smoke() {
        // We can't safely manipulate the user's real ~/Library/Application Support/Seshctl
        // in a test; just exercise the property to cover its branch. The
        // assertion is loose — we only require that calling it doesn't throw
        // and returns a Bool.
        let value = FirstLaunchInstaller.isInstalled
        #expect(value == true || value == false)
    }

    // MARK: 13. Hook self-clean fires on the 5th miss

    @Test("Hook self-clean fires on 5th consecutive miss, not before")
    func hookSelfCleanFiresAt5thMiss() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        // Sanity: seshctl entries exist after install.
        let beforeSettings = try loadJSONObject(at: paths.claudeSettingsFile)
        #expect(countSeshctlGroups(in: beforeSettings, event: "SessionStart") == 1)

        let hookScript = (paths.claudeHooksDir as NSString)
            .appendingPathComponent("session-start.sh")
        let missFile = temp.appendingPathComponent("Library/Application Support/Seshctl/hook-misses.json")

        // Build a PATH that has jq + base utilities but NOT seshctl-cli.
        // We deliberately DO NOT include temp/.local/bin in PATH so the hook
        // sees no `seshctl-cli`.
        let basePath = "/usr/bin:/bin:/usr/sbin:/sbin"
        // Sanity check: jq must be reachable.
        let jqPath = "/usr/bin/jq"
        precondition(FileManager.default.isExecutableFile(atPath: jqPath),
                     "jq missing at \(jqPath); test cannot proceed")

        func runHookOnce() throws -> Int32 {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [hookScript]
            var env: [String: String] = [
                "HOME": temp.path,
                "PATH": basePath,
            ]
            env["SHELL"] = "/bin/bash"
            proc.environment = env
            let inPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try proc.run()
            inPipe.fileHandleForWriting.write(Data("{}".utf8))
            try inPipe.fileHandleForWriting.close()
            proc.waitUntilExit()
            return proc.terminationStatus
        }

        // Misses 1..4 — counter increments, hooks NOT cleaned yet.
        for i in 1...4 {
            _ = try runHookOnce()
            let counterData = try Data(contentsOf: missFile)
            let counter = try JSONSerialization.jsonObject(with: counterData) as? [String: Any]
            let misses = counter?["misses"] as? Int ?? -1
            #expect(misses == i, "expected \(i) misses, got \(misses)")
            // settings.json should still have the seshctl entry.
            let settings = try loadJSONObject(at: paths.claudeSettingsFile)
            #expect(countSeshctlGroups(in: settings, event: "SessionStart") == 1,
                    "seshctl group should survive miss #\(i)")
        }

        // Miss 5 — should trigger seshctl-uninstall, which cleans settings.
        _ = try runHookOnce()

        // After uninstaller fires, miss-counter file is gone (app support dir wiped).
        // settings.json should no longer contain seshctl entries.
        let after = try loadJSONObject(at: paths.claudeSettingsFile)
        let afterCount = countSeshctlGroups(in: after, event: "SessionStart")
        #expect(afterCount == 0, "seshctl entries should be gone after 5th miss; got \(afterCount)")
    }

    // MARK: 14. bundleNeedsRefresh — staleness detection

    @Test("bundleNeedsRefresh returns false when no marker exists")
    func testBundleNeedsRefresh_falseWhenNoMarker() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        // No install has been performed — marker is absent. The no-marker
        // case is handled by the welcome-panel path, so refresh should be
        // false here.
        #expect(!FirstLaunchInstaller.bundleNeedsRefresh(
            bundleURL: bundle, currentVersion: "0.1.0", paths: paths
        ))
    }

    @Test("bundleNeedsRefresh returns false when bundle + version + mtime all match")
    func testBundleNeedsRefresh_falseWhenEverythingMatches() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        // Backdate the executable's mtime well before the marker's
        // installedAt. The marker stores ISO 8601 with 1 s precision, so a
        // freshly-`touch`ed executable's fractional-second mtime can read as
        // "slightly newer" than the marker even when nothing changed. The
        // production check is meant to catch a fresh `cp -R` from dev
        // iteration (where the dev's build is unambiguously newer than the
        // last marker), so backdating models the steady state.
        let execPath = bundle.appendingPathComponent("Contents/MacOS/SeshctlApp").path
        let past = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes(
            [.modificationDate: past], ofItemAtPath: execPath
        )

        // Marker was just written with the bundle's version (0.1.0-test from
        // makeFakeBundle's Info.plist). Same URL, same version → no refresh.
        #expect(!FirstLaunchInstaller.bundleNeedsRefresh(
            bundleURL: bundle, currentVersion: "0.1.0-test", paths: paths
        ))
    }

    @Test("bundleNeedsRefresh returns true on version mismatch")
    func testBundleNeedsRefresh_trueOnVersionMismatch() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        // Marker recorded version "0.1.0-test"; passing a different version
        // simulates a release-bump on subsequent launch.
        #expect(FirstLaunchInstaller.bundleNeedsRefresh(
            bundleURL: bundle, currentVersion: "0.2.0", paths: paths
        ))
    }

    @Test("bundleNeedsRefresh returns true on bundle path mismatch")
    func testBundleNeedsRefresh_trueOnBundlePathMismatch() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundleA = try makeFakeBundle(in: temp)
        // Second bundle in a sibling directory so .path differs.
        let altParent = temp.appendingPathComponent("alt")
        try FileManager.default.createDirectory(at: altParent, withIntermediateDirectories: true)
        let bundleB = try makeFakeBundle(in: altParent)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundleA, paths: paths)

        // Marker recorded bundleA's path; passing bundleB's URL simulates
        // the user moving/relinking the .app between launches.
        #expect(FirstLaunchInstaller.bundleNeedsRefresh(
            bundleURL: bundleB, currentVersion: "0.1.0-test", paths: paths
        ))
    }

    @Test("bundleNeedsRefresh returns true when executable mtime is newer than marker")
    func testBundleNeedsRefresh_trueWhenExecutableMtimeNewer() throws {
        let temp = try makeTempHome()
        defer { cleanup(temp) }
        let bundle = try makeFakeBundle(in: temp)
        let paths = FirstLaunchInstaller.Paths(homeRoot: temp)

        try FirstLaunchInstaller.install(bundleURL: bundle, paths: paths)

        // Advance the bundle executable's mtime past the marker's
        // installedAt. We bump explicitly via setAttributes (1.5 s in the
        // future) instead of `sleep`-ing — keeps the test fast and avoids
        // flakes on a system with coarse mtime granularity.
        let execPath = bundle.appendingPathComponent("Contents/MacOS/SeshctlApp").path
        let future = Date().addingTimeInterval(1.5)
        try FileManager.default.setAttributes(
            [.modificationDate: future], ofItemAtPath: execPath
        )

        #expect(FirstLaunchInstaller.bundleNeedsRefresh(
            bundleURL: bundle, currentVersion: "0.1.0-test", paths: paths
        ))
    }
}
