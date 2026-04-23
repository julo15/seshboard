import Foundation

/// Deterministic string hash helpers. Unlike Swift's built-in `hashValue`,
/// these are stable across process launches and OS versions — use them
/// anywhere identity must survive a restart (IDs persisted to disk,
/// deterministic color/bucket mapping, etc.).
public enum StableHash {
    /// djb2 — simple, fast, stable hash. Not cryptographic.
    public static func djb2(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}
