import Foundation

public struct GitContext: Sendable {
    public let repoName: String?
    public let branch: String?

    public init(repoName: String? = nil, branch: String? = nil) {
        self.repoName = repoName
        self.branch = branch
    }

    public static func detect(directory: String) -> GitContext {
        let repoName = resolveRepoName(directory: directory)
        let branch = resolveBranch(directory: directory)
        return GitContext(repoName: repoName, branch: branch)
    }

    // MARK: - Private

    private static func resolveRepoName(directory: String) -> String? {
        if let remoteURL = runGit(directory: directory, arguments: ["remote", "get-url", "origin"]) {
            return parseRepoName(from: remoteURL)
        }
        if let toplevel = runGit(directory: directory, arguments: ["rev-parse", "--show-toplevel"]) {
            return URL(fileURLWithPath: toplevel).lastPathComponent
        }
        return nil
    }

    private static func resolveBranch(directory: String) -> String? {
        guard let branch = runGit(directory: directory, arguments: ["rev-parse", "--abbrev-ref", "HEAD"]) else {
            return nil
        }
        return branch == "HEAD" ? nil : branch
    }

    static func parseRepoName(from remoteURL: String) -> String? {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        let lastComponent: String
        if url.contains("://") {
            // HTTPS: https://github.com/user/seshctl.git
            guard let parsed = URL(string: url) else { return nil }
            lastComponent = parsed.lastPathComponent
        } else {
            // SSH: git@github.com:user/seshctl.git
            lastComponent = String(url.split(separator: "/").last ?? "")
        }

        guard !lastComponent.isEmpty else { return nil }

        if lastComponent.hasSuffix(".git") {
            return String(lastComponent.dropLast(4))
        }
        return lastComponent
    }

    private static func runGit(directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
