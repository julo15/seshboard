import Foundation
import Testing

@testable import SeshctlCore

@Suite("VSCodeWindowMap")
struct VSCodeWindowMapTests {
    private static func makeEntry(shellPid: Int, startTime: Int, folders: [String]) -> Data {
        let entry = VSCodeWindowMap.Entry(shellPid: shellPid, startTime: startTime, workspaceFolders: folders)
        return try! JSONEncoder().encode(entry)
    }

    @Test("Direct hit on starting pid")
    func directHit() {
        let dir = "/maps"
        let files: [String: Data] = [
            "/maps/100.json": Self.makeEntry(shellPid: 100, startTime: 1_000, folders: ["/work/repo"])
        ]
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: dir,
            parentPid: { _ in 0 },
            startTime: { p in p == 100 ? 1_000 : nil },
            readFile: { files[$0] }
        )
        #expect(result == "/work/repo")
    }

    @Test("Ancestor hit")
    func ancestorHit() {
        let dir = "/maps"
        let files: [String: Data] = [
            "/maps/500.json": Self.makeEntry(shellPid: 500, startTime: 2_000, folders: ["/work/parent"])
        ]
        let parents: [Int: Int] = [100: 200, 200: 500, 500: 2]
        let starts: [Int: Int] = [100: 111, 200: 222, 500: 2_000]
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: dir,
            parentPid: { parents[$0] ?? 0 },
            startTime: { starts[$0] },
            readFile: { files[$0] }
        )
        #expect(result == "/work/parent")
    }

    @Test("startTime mismatch skips entry and walk continues")
    func startTimeMismatch() {
        let dir = "/maps"
        let files: [String: Data] = [
            "/maps/100.json": Self.makeEntry(shellPid: 100, startTime: 1_000, folders: ["/stale"]),
            "/maps/200.json": Self.makeEntry(shellPid: 200, startTime: 2_000, folders: ["/fresh"])
        ]
        let parents: [Int: Int] = [100: 200, 200: 2]
        let starts: [Int: Int] = [100: 9_999, 200: 2_000]
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: dir,
            parentPid: { parents[$0] ?? 0 },
            startTime: { starts[$0] },
            readFile: { files[$0] }
        )
        #expect(result == "/fresh")
    }

    @Test("No matching file returns nil")
    func noMatchingFile() {
        let result = VSCodeWindowMap.lookup(
            startPid: 42,
            directory: "/maps",
            parentPid: { _ in 1 },
            startTime: { _ in 123 },
            readFile: { _ in nil }
        )
        #expect(result == nil)
    }

    @Test("Depth limit respected")
    func depthLimit() {
        let dir = "/maps"
        let files: [String: Data] = [
            "/maps/5.json": Self.makeEntry(shellPid: 5, startTime: 500, folders: ["/deep"])
        ]
        let parents: [Int: Int] = [1000: 1001, 1001: 1002, 1002: 1003, 1003: 5]
        let starts: [Int: Int] = [1000: 1, 1001: 2, 1002: 3, 1003: 4, 5: 500]
        let result = VSCodeWindowMap.lookup(
            startPid: 1000,
            directory: dir,
            maxDepth: 3,
            parentPid: { parents[$0] ?? 0 },
            startTime: { starts[$0] },
            readFile: { files[$0] }
        )
        #expect(result == nil)
    }

    @Test("pid <= 1 terminates walk")
    func pidOneTerminates() {
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: "/maps",
            parentPid: { _ in 1 },
            startTime: { _ in 0 },
            readFile: { _ in nil }
        )
        #expect(result == nil)
    }

    @Test("Self-loop guard")
    func selfLoopGuard() {
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: "/maps",
            parentPid: { _ in 100 },
            startTime: { _ in 0 },
            readFile: { _ in nil }
        )
        #expect(result == nil)
    }

    @Test("Empty workspaceFolders returns nil and walk continues")
    func emptyWorkspaceFoldersContinues() {
        let dir = "/maps"
        let files: [String: Data] = [
            "/maps/100.json": Self.makeEntry(shellPid: 100, startTime: 1_000, folders: []),
            "/maps/200.json": Self.makeEntry(shellPid: 200, startTime: 2_000, folders: ["/found"])
        ]
        let parents: [Int: Int] = [100: 200, 200: 2]
        let starts: [Int: Int] = [100: 1_000, 200: 2_000]
        let result = VSCodeWindowMap.lookup(
            startPid: 100,
            directory: dir,
            parentPid: { parents[$0] ?? 0 },
            startTime: { starts[$0] },
            readFile: { files[$0] }
        )
        #expect(result == "/found")
    }

    @Test("defaultDirectory respects env var")
    func defaultDirectoryEnvOverride() {
        let result = VSCodeWindowMap.defaultDirectory(environment: ["SESHCTL_VSCODE_WINDOWS_DIR": "/custom/dir"])
        #expect(result == "/custom/dir")
    }

    @Test("defaultDirectory falls back to default when env unset or empty")
    func defaultDirectoryFallback() {
        let expected = NSString(string: "~/.local/share/seshctl/vscode-windows").expandingTildeInPath
        #expect(VSCodeWindowMap.defaultDirectory(environment: [:]) == expected)
        #expect(VSCodeWindowMap.defaultDirectory(environment: ["SESHCTL_VSCODE_WINDOWS_DIR": ""]) == expected)
    }
}
