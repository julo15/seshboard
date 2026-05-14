import AppKit
import SeshctlCore

/// Production `AppLocator` that resolves bundle IDs via Launch Services.
public struct NSWorkspaceAppLocator: AppLocator {
    public init() {}
    public func appURL(forBundleId bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }
}
