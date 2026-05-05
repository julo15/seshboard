import Foundation

/// Pure-logic parsers for `cmux tree --json` output. The CLI invocation that
/// produces the JSON lives in `TerminalController` (system-touching); the
/// shape-walking lives here so it can be unit-tested without a system bus.
public enum CmuxTree {

    /// Walk a `cmux tree --json` payload to find the `pane_id` that contains a
    /// surface with the given UUID. Returns nil if the surface is not found.
    public static func findPaneId(json: String, surfaceId: String) -> String? {
        for surface in walkSurfaces(json: json) {
            if let id = surface["id"] as? String, id == surfaceId {
                return surface["pane_id"] as? String
            }
        }
        return nil
    }

    /// Return the set of surface UUIDs that live in the given pane.
    public static func surfaceIds(inPane paneId: String, treeJSON: String) -> Set<String> {
        var ids = Set<String>()
        for surface in walkSurfaces(json: treeJSON) where (surface["pane_id"] as? String) == paneId {
            if let id = surface["id"] as? String { ids.insert(id) }
        }
        return ids
    }

    private static func walkSurfaces(json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var out: [[String: Any]] = []
        for window in (root["windows"] as? [[String: Any]]) ?? [] {
            for workspace in (window["workspaces"] as? [[String: Any]]) ?? [] {
                for pane in (workspace["panes"] as? [[String: Any]]) ?? [] {
                    for surface in (pane["surfaces"] as? [[String: Any]]) ?? [] {
                        out.append(surface)
                    }
                }
            }
        }
        return out
    }
}
