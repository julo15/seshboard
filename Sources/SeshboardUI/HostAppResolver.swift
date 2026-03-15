import AppKit
import Foundation
import SeshboardCore

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
        // Second: try live PID lookup
        else if let pid = session.pid {
            info = lookupHostApp(pid: pid)
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

    private func lookupHostApp(pid: Int) -> HostAppInfo {
        var currentPid = pid_t(pid)
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: currentPid),
               app.activationPolicy == .regular,
               let bundleId = app.bundleIdentifier {
                return HostAppInfo(
                    bundleId: bundleId,
                    name: app.localizedName ?? bundleId,
                    icon: app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
                )
            }

            let parent = getParentPid(currentPid)
            if parent <= 1 || parent == currentPid { break }
            currentPid = parent
        }

        // Fallback: check known terminals
        let knownTerminals: [(String, String)] = [
            ("com.apple.Terminal", "Terminal"),
            ("com.googlecode.iterm2", "iTerm2"),
            ("dev.warp.Warp-Stable", "Warp"),
        ]

        for (bundleId, name) in knownTerminals {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                return HostAppInfo(
                    bundleId: bundleId,
                    name: app.localizedName ?? name,
                    icon: app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
                )
            }
        }

        return .unknown
    }

    private func getParentPid(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}
