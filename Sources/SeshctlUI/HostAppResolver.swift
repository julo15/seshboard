import AppKit
import SeshctlCore

public struct HostAppInfo: Sendable {
    public let bundleId: String
    public let name: String
    public let icon: NSImage

    public static let unknown = HostAppInfo(
        bundleId: "",
        name: "Unknown",
        icon: NSImage(named: NSImage.applicationIconName) ?? NSImage()
    )
}

/// Resolves the host terminal app for a session, using stored DB values first,
/// falling back to PID-based lookup for live processes.
@MainActor
public final class HostAppResolver: ObservableObject {
    private var cache: [String: HostAppInfo] = [:]  // keyed by session ID

    public init() {}

    public func resolve(session: Session) -> HostAppInfo {
        if let cached = cache[session.id] { return cached }

        let info: HostAppInfo

        // First: use stored host app info from the database
        if let bundleId = session.hostAppBundleId, !bundleId.isEmpty {
            let icon = iconForBundleId(bundleId)
            info = HostAppInfo(
                bundleId: bundleId,
                name: session.hostAppName ?? bundleId,
                icon: icon
            )
        }
        // Second: try live PID lookup via TerminalController
        else if let pid = session.pid,
                let bundleId = TerminalController.findAppBundleId(
                    for: pid, env: TerminalController.environment
                ) {
            let icon = iconForBundleId(bundleId)
            let name = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleId
            ).first?.localizedName ?? bundleId
            info = HostAppInfo(bundleId: bundleId, name: name, icon: icon)
        } else {
            info = .unknown
        }

        cache[session.id] = info
        return info
    }

    private func iconForBundleId(_ bundleId: String) -> NSImage {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: appUrl.path)
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}
