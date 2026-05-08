import Foundation

/// cmux's session windowId column packs workspace + surface UUIDs as
/// "<workspaceId>|<surfaceId>". `|` is safe because UUIDs cannot contain it.
/// Pre-surface (legacy) sessions stored only the workspace UUID.
public struct CmuxWindowID: Equatable, Sendable {
    public let workspaceId: String
    public let surfaceId: String?

    public init(workspaceId: String, surfaceId: String?) {
        self.workspaceId = workspaceId
        self.surfaceId = surfaceId
    }

    public static func parse(_ windowId: String?) -> CmuxWindowID? {
        guard let windowId, !windowId.isEmpty else { return nil }
        guard let sep = windowId.firstIndex(of: "|") else {
            return CmuxWindowID(workspaceId: windowId, surfaceId: nil)
        }
        let ws = String(windowId[..<sep])
        let raw = String(windowId[windowId.index(after: sep)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CmuxWindowID(workspaceId: ws, surfaceId: raw.isEmpty ? nil : raw)
    }
}
