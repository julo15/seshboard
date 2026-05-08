import ArgumentParser
import Foundation
import SeshctlCore

// MARK: - Install
//
// Thin CLI wrappers around `FirstLaunchInstaller` (in `SeshctlCore`). The
// implementation moved out of this file so the GUI app can reuse it from
// `AppDelegate.applicationDidFinishLaunching`.

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install seshctl hooks (and optionally the full first-launch setup)."
    )

    @Flag(help: "Install Claude Code hooks.")
    var claude = false

    @Flag(help: "Install Codex hooks.")
    var codex = false

    @Flag(help: "Install all supported CLI hooks (Claude + Codex).")
    var all = false

    @Flag(help: "Full install: hooks + ~/.local/bin/seshctl symlink + standalone uninstaller + marker file. Use this from a freshly-installed bundle.")
    var full = false

    func run() throws {
        if full {
            if claude || codex || all {
                throw ValidationError("--full is mutually exclusive with --claude/--codex/--all.")
            }
            let result = try FirstLaunchInstaller.install(bundleURL: nil)
            for action in result.actions {
                print("  \(describe(action))")
            }
            print("seshctl installed.")
            return
        }

        let installClaude = claude || all
        let installCodex = codex || all

        if !installClaude && !installCodex {
            throw ValidationError("Specify --claude, --codex, --all, or --full.")
        }

        if installClaude {
            try FirstLaunchInstaller.installClaudeHooks()
            print("Claude Code: hooks installed at \(FirstLaunchInstaller.defaultPaths.claudeHooksDir)/")
        }

        if installCodex {
            try FirstLaunchInstaller.installCodexHooks()
            print("Codex: hooks installed at \(FirstLaunchInstaller.defaultPaths.codexHooksDir)/")
        }
    }
}

// MARK: - Uninstall

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove seshctl hooks (and optionally the full first-launch setup)."
    )

    @Flag(help: "Uninstall Claude Code hooks.")
    var claude = false

    @Flag(help: "Uninstall Codex hooks.")
    var codex = false

    @Flag(help: "Uninstall all supported CLI hooks (Claude + Codex).")
    var all = false

    @Flag(help: "Full uninstall: hooks + symlinks + uninstaller + marker file + ~/Library/Application Support/Seshctl. Leaves seshctl.db and codex_hooks=true alone.")
    var full = false

    func run() throws {
        if full {
            if claude || codex || all {
                throw ValidationError("--full is mutually exclusive with --claude/--codex/--all.")
            }
            let result = try FirstLaunchInstaller.uninstall()
            for action in result.actions {
                print("  \(describe(action))")
            }
            print("seshctl uninstalled.")
            return
        }

        let uninstallClaude = claude || all
        let uninstallCodex = codex || all

        if !uninstallClaude && !uninstallCodex {
            throw ValidationError("Specify --claude, --codex, --all, or --full.")
        }

        if uninstallClaude {
            try FirstLaunchInstaller.uninstallClaudeHooks()
            print("Claude Code: removed seshctl hooks from \(FirstLaunchInstaller.defaultPaths.claudeSettingsFile)")
        }

        if uninstallCodex {
            try FirstLaunchInstaller.uninstallCodexHooks()
            print("Codex: removed seshctl hooks from \(FirstLaunchInstaller.defaultPaths.codexSettingsFile)")
        }
    }
}

// MARK: - Action description

private func describe(_ action: FirstLaunchInstaller.Action) -> String {
    switch action {
    case .symlinkCreated(let path, let target):
        return "symlink created: \(path) → \(target)"
    case .symlinkReplaced(let path, let target):
        return "symlink updated: \(path) → \(target)"
    case .migratedRealFileToSymlink(let path):
        return "migrated stale file to symlink: \(path)"
    case .uninstallerScriptWritten(let path):
        return "wrote uninstaller: \(path)"
    case .hookScriptWritten(let path):
        return "wrote hook script: \(path)"
    case .hookRegistered(let llm, let event):
        return "\(llm): registered \(event) hook"
    case .hookAlreadyRegistered(let llm, let event):
        return "\(llm): \(event) already registered"
    case .codexConfigUpdated:
        return "set codex_hooks = true in ~/.agents/config.toml"
    case .codexConfigAlreadySet:
        return "codex_hooks = true already set"
    case .markerFileWritten(let path):
        return "wrote marker file: \(path)"
    case .removedHookEntry(let llm, let event):
        return "\(llm): removed \(event) hook entry"
    case .removedSymlink(let path):
        return "removed symlink: \(path)"
    case .removedFile(let path):
        return "removed file: \(path)"
    case .removedDirectory(let path):
        return "removed directory: \(path)"
    case .noted(let msg):
        return msg
    }
}
