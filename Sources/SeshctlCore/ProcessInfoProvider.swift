import Darwin
import Foundation

/// Abstracts macOS process-info lookups (parent PID, start time) so call sites can be unit-tested.
public protocol ProcessInfoProvider: Sendable {
    /// Returns the parent PID of the given PID, or 0 on failure.
    func parentPid(of pid: Int) -> Int
    /// Returns the process start time in UTC epoch seconds, or nil on failure.
    func startTime(of pid: Int) -> Int?
}

public struct RealProcessInfoProvider: ProcessInfoProvider {
    public init() {}

    public func parentPid(of pid: Int) -> Int {
        guard let info = Self.bsdInfo(for: pid) else { return 0 }
        return Int(info.pbi_ppid)
    }

    public func startTime(of pid: Int) -> Int? {
        guard let info = Self.bsdInfo(for: pid) else { return nil }
        return Int(info.pbi_start_tvsec)
    }

    private static func bsdInfo(for pid: Int) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, &info, Int32(size))
        return result == size ? info : nil
    }
}
