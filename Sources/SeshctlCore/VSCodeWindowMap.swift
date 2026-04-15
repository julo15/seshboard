import Foundation

public enum VSCodeWindowMap {
    public struct Entry: Codable {
        public let shellPid: Int
        public let startTime: Int
        public let workspaceFolders: [String]
    }

    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["SESHCTL_VSCODE_WINDOWS_DIR"], !override.isEmpty {
            return override
        }
        return NSString(string: "~/.local/share/seshctl/vscode-windows").expandingTildeInPath
    }

    public static func lookup(
        startPid: Int,
        directory: String,
        maxDepth: Int = 10,
        parentPid: (Int) -> Int,
        startTime: (Int) -> Int?,
        readFile: (String) -> Data?
    ) -> String? {
        var current = startPid
        var visited = Set<Int>()
        for _ in 0..<maxDepth {
            if visited.contains(current) { return nil }
            visited.insert(current)

            let path = "\(directory)/\(current).json"
            if let data = readFile(path),
               let entry = try? JSONDecoder().decode(Entry.self, from: data),
               let live = startTime(current),
               entry.startTime == live,
               let folder = entry.workspaceFolders.first {
                return folder
            }

            let parent = parentPid(current)
            if parent <= 1 || parent == current { return nil }
            current = parent
        }
        return nil
    }
}
