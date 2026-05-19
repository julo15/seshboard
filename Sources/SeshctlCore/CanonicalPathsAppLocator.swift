import Foundation

/// Foundation-only AppLocator used by CLI contexts where AppKit (and thus
/// `NSWorkspace`) isn't available. Maps the supported editor bundle IDs to
/// their canonical `/Applications/<name>.app` paths and returns the URL only
/// if the directory actually exists on disk.
///
/// The PATH fallback inside `ExtensionInstaller.resolveEditorCLI` still kicks
/// in when this locator returns nil, so users who relocated the editor or
/// only have its CLI shim installed continue to work — they just lose the
/// "in-bundle CLI preferred over PATH" optimization.
///
/// `applicationsRoot` is injected for tests; production passes the default
/// `/Applications` URL. Uses `FileManager.default` directly — keeping it off
/// the struct's stored properties so it stays trivially `Sendable`.
public struct CanonicalPathsAppLocator: AppLocator {
    private let applicationsRoot: URL

    public init(applicationsRoot: URL = URL(fileURLWithPath: "/Applications")) {
        self.applicationsRoot = applicationsRoot
    }

    public func appURL(forBundleId bundleId: String) -> URL? {
        guard let name = Self.canonicalAppFilename(forBundleId: bundleId) else {
            return nil
        }
        let candidate = applicationsRoot.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return candidate
    }

    /// Hard-coded mapping of supported editor bundle IDs to their `.app`
    /// directory names. Mirrors the canonical paths the standalone shell
    /// uninstaller probes, so the two stay aligned. Non-editor bundle IDs
    /// (terminals, unknown apps) return nil.
    static func canonicalAppFilename(forBundleId bundleId: String) -> String? {
        switch bundleId {
        case TerminalApp.vscode.bundleId:
            return "Visual Studio Code.app"
        case TerminalApp.vscodeInsiders.bundleId:
            return "Visual Studio Code - Insiders.app"
        case TerminalApp.cursor.bundleId:
            return "Cursor.app"
        default:
            return nil
        }
    }
}
