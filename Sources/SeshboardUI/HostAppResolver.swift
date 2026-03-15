import AppKit
import Foundation

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

/// Resolves the host terminal app for a given PID and caches results.
@MainActor
public final class HostAppResolver: ObservableObject {
    private var cache: [Int: HostAppInfo] = [:]

    public init() {}

    public func resolve(pid: Int?) -> HostAppInfo {
        guard let pid else { return .unknown }

        if let cached = cache[pid] { return cached }

        let info = lookupHostApp(pid: pid)
        cache[pid] = info
        return info
    }

    /// Clear cache entries for dead PIDs.
    public func evictDead() {
        cache = cache.filter { pid, _ in
            kill(Int32(pid), 0) == 0
        }
    }

    private func lookupHostApp(pid: Int) -> HostAppInfo {
        // Walk up the process tree to find the GUI app
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
