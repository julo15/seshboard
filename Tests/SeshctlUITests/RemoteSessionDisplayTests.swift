import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

private func makeRemote(
    title: String = "Remote session",
    repoUrl: String? = nil,
    branches: [String] = []
) -> RemoteClaudeCodeSession {
    RemoteClaudeCodeSession(
        id: "cse_\(UUID().uuidString)",
        title: title,
        model: "claude-sonnet-4",
        repoUrl: repoUrl,
        branches: branches,
        status: "active",
        workerStatus: "idle",
        connectionStatus: "connected",
        lastEventAt: Date(),
        createdAt: Date(),
        unread: false,
        lastReadAt: nil,
        environmentKind: ""
    )
}

// MARK: - senderDisplay

@Suite("RemoteClaudeCodeSession.senderDisplay")
struct RemoteSenderDisplayTests {

    @Test("repoUrl present → repoPart from short name, dirSuffix=nil")
    func repoUrlPresent() {
        let r = makeRemote(repoUrl: "https://github.com/foo/bar.git")
        #expect(r.senderDisplay == SenderDisplay(repoPart: "bar", dirSuffix: nil))
    }

    @Test("repoUrl present without .git suffix → repoPart=last path component")
    func repoUrlWithoutGitSuffix() {
        let r = makeRemote(repoUrl: "https://github.com/julo15/qbk-scheduler")
        #expect(r.senderDisplay == SenderDisplay(repoPart: "qbk-scheduler", dirSuffix: nil))
    }

    @Test("repoUrl nil → repoPart=\"Remote\", dirSuffix=nil")
    func repoUrlNil() {
        let r = makeRemote(repoUrl: nil)
        #expect(r.senderDisplay == SenderDisplay(repoPart: "Remote", dirSuffix: nil))
    }
}

// MARK: - branchDisplay

@Suite("RemoteClaudeCodeSession.branchDisplay")
struct RemoteBranchDisplayTests {

    @Test("Non-empty branches array → returns first")
    func nonEmptyBranches() {
        let r = makeRemote(branches: ["main", "feature/x"])
        #expect(r.branchDisplay == "main")
    }

    @Test("Empty branches array → returns nil (signals line-2 collapse)")
    func emptyBranches() {
        let r = makeRemote(branches: [])
        #expect(r.branchDisplay == nil)
    }
}

// MARK: - previewContent

@Suite("RemoteClaudeCodeSession.previewContent")
struct RemotePreviewContentTests {

    @Test("Always returns .reply(title) — no priority chain on remote rows")
    func alwaysReplyOfTitle() {
        let r = makeRemote(title: "Investigate flaky test")
        #expect(r.previewContent == .reply("Investigate flaky test"))
    }

    @Test("Empty title still returns .reply(\"\") — caller decides how to render")
    func emptyTitle() {
        let r = makeRemote(title: "")
        #expect(r.previewContent == .reply(""))
    }
}
