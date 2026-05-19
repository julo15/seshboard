import Foundation

/// Stable extension identifier in the editor's extension registry, used by
/// `--list-extensions` output parsing and `--uninstall-extension`.
public let seshctlExtensionId = "julo15.seshctl"

// MARK: - Status types

public enum EditorExtensionStatus: Equatable, Sendable {
    case notInstalled
    case installed(version: String)
    case outdated(installed: String, bundled: String)
    /// The editor app is installed but we couldn't locate its CLI binary
    /// (neither inside the .app nor on PATH). Action buttons should be disabled.
    case cliUnavailable
}

public struct EditorIntegration: Sendable, Equatable {
    public let app: TerminalApp
    public let appURL: URL
    public let status: EditorExtensionStatus
    public init(app: TerminalApp, appURL: URL, status: EditorExtensionStatus) {
        self.app = app
        self.appURL = appURL
        self.status = status
    }
}

public enum InstallError: Error, Equatable {
    case cliNotFound
    case bundledVsixMissing
    case subprocessFailed(stderr: String, status: Int32)
    case timeout
}

// MARK: - Injection seams

public protocol ExtensionRunner: Sendable {
    func run(path: String, args: [String], timeout: TimeInterval) -> ShellRunner.Result?
}

public struct DefaultExtensionRunner: ExtensionRunner {
    public init() {}
    public func run(path: String, args: [String], timeout: TimeInterval) -> ShellRunner.Result? {
        ShellRunner.run(path: path, args: args, timeout: timeout)
    }
}

public protocol AppLocator: Sendable {
    /// Resolve the on-disk .app URL for a registered macOS bundle identifier,
    /// or nil if the app isn't installed / not registered with Launch Services.
    func appURL(forBundleId bundleId: String) -> URL?
}

// MARK: - ExtensionInstaller

/// Stateless beyond injected immutable dependencies; safe to share across queues.
public final class ExtensionInstaller: @unchecked Sendable {
    private let runner: ExtensionRunner
    private let appLocator: AppLocator
    private let fileManager: FileManager

    public init(runner: ExtensionRunner = DefaultExtensionRunner(),
                appLocator: AppLocator,
                fileManager: FileManager = .default) {
        self.runner = runner
        self.appLocator = appLocator
        self.fileManager = fileManager
    }

    // MARK: Bundle layout

    public func bundledVsixURL(bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/extensions/seshctl.vsix")
    }

    /// Reads the bundled version sidecar at
    /// `Contents/Resources/extensions/seshctl.vsix.version`. Returns nil if
    /// missing or unreadable.
    public func bundledVersion(bundleURL: URL) -> String? {
        let sidecarURL = bundledVsixURL(bundleURL: bundleURL)
            .appendingPathExtension("version")
        guard let data = try? Data(contentsOf: sidecarURL),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: CLI resolution

    /// Resolve the editor's CLI binary path:
    /// 1) Look inside the .app at Contents/Resources/app/bin/<name>.
    /// 2) Fall back to `/usr/bin/which <name>` on PATH.
    /// Returns nil if both miss.
    public func resolveEditorCLI(editor: TerminalApp) -> URL? {
        guard let cliName = editor.extensionCLIName else { return nil }

        if let appURL = appLocator.appURL(forBundleId: editor.bundleId) {
            let bundledCLI = appURL
                .appendingPathComponent("Contents/Resources/app/bin")
                .appendingPathComponent(cliName)
            if fileManager.fileExists(atPath: bundledCLI.path) {
                return bundledCLI
            }
        }

        if let whichResult = runner.run(path: "/usr/bin/which", args: [cliName], timeout: 2),
           whichResult.status == 0 {
            let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    // MARK: Survey

    /// One row per editor *whose .app is installed on this Mac*.
    /// - `cliUnavailable` if the .app is present but the CLI binary can't be found.
    /// - Otherwise queries `<cli> --list-extensions --show-versions` and maps the
    ///   `julo15.seshctl` line into `.installed(version:)` / `.outdated(...)`
    ///   / `.notInstalled`. Bundled version comes from the sidecar; if the
    ///   sidecar is missing, never report `.outdated` (treat any installed
    ///   version as up-to-date).
    public func surveyInstalledEditors(bundleURL: URL) -> [EditorIntegration] {
        let bundledVer = bundledVersion(bundleURL: bundleURL)
        var integrations: [EditorIntegration] = []
        for editor in TerminalApp.allVSCodeVariants {
            guard let appURL = appLocator.appURL(forBundleId: editor.bundleId) else {
                continue
            }
            guard let cliURL = resolveEditorCLI(editor: editor) else {
                integrations.append(EditorIntegration(app: editor, appURL: appURL, status: .cliUnavailable))
                continue
            }
            let installedVersion = queryInstalledVersion(cliPath: cliURL.path)
            let status = computeStatus(installed: installedVersion, bundled: bundledVer)
            integrations.append(EditorIntegration(app: editor, appURL: appURL, status: status))
        }
        return integrations
    }

    /// Runs `<cli> --list-extensions --show-versions` and returns the version
    /// portion of the `julo15.seshctl@<version>` line, or nil if not present /
    /// if the subprocess failed. Never throws — survey must not throw.
    private func queryInstalledVersion(cliPath: String) -> String? {
        guard let result = runner.run(
            path: cliPath,
            args: ["--list-extensions", "--show-versions"],
            timeout: 5
        ) else {
            return nil
        }
        guard result.status == 0 else { return nil }
        return Self.parseInstalledVersion(output: result.stdout)
    }

    /// Public to allow easy testing in Step 7. Splits on newline, finds a line
    /// whose `@`-prefix exactly matches `seshctlExtensionId`, returns the suffix.
    static func parseInstalledVersion(output: String) -> String? {
        for rawLine in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let atRange = line.range(of: "@") else { continue }
            let prefix = line[line.startIndex..<atRange.lowerBound]
            if prefix == seshctlExtensionId {
                let suffix = line[atRange.upperBound..<line.endIndex]
                let trimmed = suffix.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func computeStatus(installed: String?, bundled: String?) -> EditorExtensionStatus {
        guard let installed else { return .notInstalled }
        guard let bundled else { return .installed(version: installed) }
        if installed == bundled {
            return .installed(version: installed)
        }
        return .outdated(installed: installed, bundled: bundled)
    }

    // MARK: Mutate

    /// Runs `<cli> --install-extension <vsix> --force` (30s timeout).
    /// Throws on nonzero status with stderr captured, or on missing CLI / vsix.
    /// On success re-queries via the CLI and returns the fresh status.
    @discardableResult
    public func install(editor: TerminalApp, bundleURL: URL) throws -> EditorExtensionStatus {
        let vsixURL = bundledVsixURL(bundleURL: bundleURL)
        guard fileManager.fileExists(atPath: vsixURL.path) else {
            throw InstallError.bundledVsixMissing
        }
        guard let cliURL = resolveEditorCLI(editor: editor) else {
            throw InstallError.cliNotFound
        }
        guard let result = runner.run(
            path: cliURL.path,
            args: ["--install-extension", vsixURL.path, "--force"],
            timeout: 30
        ) else {
            throw InstallError.timeout
        }
        guard result.status == 0 else {
            throw InstallError.subprocessFailed(stderr: result.stderr, status: result.status)
        }
        let installedVersion = queryInstalledVersion(cliPath: cliURL.path)
        let bundledVer = bundledVersion(bundleURL: bundleURL)
        return computeStatus(installed: installedVersion, bundled: bundledVer)
    }

    /// Runs `<cli> --uninstall-extension julo15.seshctl`. Idempotent — a nonzero
    /// exit whose stderr includes "not installed" or "is not installed" is
    /// treated as success.
    public func uninstall(editor: TerminalApp) throws {
        guard let cliURL = resolveEditorCLI(editor: editor) else {
            throw InstallError.cliNotFound
        }
        guard let result = runner.run(
            path: cliURL.path,
            args: ["--uninstall-extension", seshctlExtensionId],
            timeout: 30
        ) else {
            throw InstallError.timeout
        }
        if result.status == 0 { return }
        let lowerStderr = result.stderr.lowercased()
        if lowerStderr.contains("not installed") {
            return
        }
        throw InstallError.subprocessFailed(stderr: result.stderr, status: result.status)
    }

    /// Background-safe: iterates supported editors, and for any whose CLI
    /// currently reports `julo15.seshctl` installed, runs the editor's
    /// `--uninstall-extension` verb. Returns a list of timestamped log lines
    /// for `appendInstallLog`. Editors without the extension installed (or
    /// without a discoverable CLI) are skipped silently — this mirrors
    /// `refreshExistingInstalls`'s "only touch opted-in editors" invariant.
    ///
    /// Does NOT require the Seshctl.app bundle to exist on disk: this method
    /// reads state purely from the editors. AppDelegate's uninstall flow
    /// calls this before tearing down `FirstLaunchInstaller` state so the
    /// editor side is cleaned up while we still have process context.
    public func uninstallAllEditorExtensions() -> [String] {
        var logs: [String] = []
        for editor in TerminalApp.allVSCodeVariants {
            guard appLocator.appURL(forBundleId: editor.bundleId) != nil else { continue }
            guard let cliURL = resolveEditorCLI(editor: editor) else { continue }
            guard let installedVersion = queryInstalledVersion(cliPath: cliURL.path) else {
                continue
            }
            // Lines are returned without a timestamp prefix — the caller owns
            // log framing. AppDelegate's `appendInstallLog` adds its own
            // ISO8601 prefix; CLI prints them as-is to stdout.
            let prefix = "extension uninstall: \(editor.displayName) (was \(installedVersion))"
            do {
                try uninstall(editor: editor)
                logs.append("\(prefix) (success)")
            } catch let error as InstallError {
                logs.append("\(prefix) (FAILED: \(describe(error)))")
            } catch {
                logs.append("\(prefix) (FAILED: \(error.localizedDescription))")
            }
        }
        return logs
    }

    /// Background-safe: scans all installed editors and silently `install`s any
    /// whose installed version differs from the bundled version. Returns a
    /// list of timestamped log lines for `appendInstallLog`. Editors that
    /// don't have the extension installed are left alone (silent refresh only
    /// applies to editors the user opted into).
    public func refreshExistingInstalls(bundleURL: URL) -> [String] {
        var logs: [String] = []
        let integrations = surveyInstalledEditors(bundleURL: bundleURL)
        for integration in integrations {
            guard case let .outdated(installed, bundled) = integration.status else { continue }
            // Lines are returned without a timestamp prefix — caller owns it.
            let prefix = "extension refresh: \(integration.app.displayName) \(installed) -> \(bundled)"
            do {
                _ = try install(editor: integration.app, bundleURL: bundleURL)
                logs.append("\(prefix) (success)")
            } catch let error as InstallError {
                logs.append("\(prefix) (FAILED: \(describe(error)))")
            } catch {
                logs.append("\(prefix) (FAILED: \(error.localizedDescription))")
            }
        }
        return logs
    }

    private func describe(_ error: InstallError) -> String {
        switch error {
        case .cliNotFound: return "CLI not found"
        case .bundledVsixMissing: return "bundled vsix missing"
        case .subprocessFailed(let stderr, let status):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "subprocess exited \(status)"
            }
            return "subprocess exited \(status): \(trimmed)"
        case .timeout: return "timeout"
        }
    }
}
