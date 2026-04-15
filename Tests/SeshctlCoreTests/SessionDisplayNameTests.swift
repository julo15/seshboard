import Foundation
import Testing

@testable import SeshctlCore

@Suite("Session.displayName")
struct SessionDisplayNameTests {
    private func makeSession(
        gitRepoName: String? = nil,
        directory: String,
        gitBranch: String? = nil
    ) -> Session {
        Session(
            id: "test",
            conversationId: nil,
            tool: .claude,
            directory: directory,
            launchDirectory: nil,
            hostWorkspaceFolder: nil,
            lastAsk: nil,
            lastReply: nil,
            status: .idle,
            pid: nil,
            hostAppBundleId: nil,
            hostAppName: nil,
            windowId: nil,
            transcriptPath: nil,
            gitRepoName: gitRepoName,
            gitBranch: gitBranch,
            startedAt: Date(),
            updatedAt: Date(),
            lastReadAt: nil
        )
    }

    @Test("Normal clone shows repo and branch")
    func normalClone() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/Users/me/seshctl",
            gitBranch: "main"
        )
        #expect(session.displayName == "seshctl · main")
    }

    @Test("Feature branch shows repo and branch")
    func featureBranch() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/Users/me/seshctl",
            gitBranch: "feat-auth"
        )
        #expect(session.displayName == "seshctl · feat-auth")
    }

    @Test("Renamed clone shows repo, dir, and branch")
    func renamedClone() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/Users/me/my-folder",
            gitBranch: "main"
        )
        #expect(session.displayName == "seshctl · my-folder · main")
    }

    @Test("Renamed clone with feature branch")
    func renamedCloneFeatureBranch() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/Users/me/my-folder",
            gitBranch: "feat-auth"
        )
        #expect(session.displayName == "seshctl · my-folder · feat-auth")
    }

    @Test("Worktree shows repo, dir, and branch")
    func worktree() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/tmp/.worktree-abc",
            gitBranch: "feat-auth"
        )
        #expect(session.displayName == "seshctl · .worktree-abc · feat-auth")
    }

    @Test("Local repo without remote shows repo and branch")
    func localRepoNoRemote() {
        let session = makeSession(
            gitRepoName: "experiments",
            directory: "/Users/me/experiments",
            gitBranch: "main"
        )
        #expect(session.displayName == "experiments · main")
    }

    @Test("Not a git repo shows directory name only")
    func notAGitRepo() {
        let session = makeSession(
            directory: "/Users/me/random-dir"
        )
        #expect(session.displayName == "random-dir")
    }

    @Test("Repo name with nil branch shows repo only")
    func repoNameNilBranch() {
        let session = makeSession(
            gitRepoName: "seshctl",
            directory: "/Users/me/seshctl"
        )
        #expect(session.displayName == "seshctl")
    }

    @Test("Nil repo name with branch set shows directory name only")
    func nilRepoNameWithBranch() {
        let session = makeSession(
            directory: "/Users/me/foo",
            gitBranch: "main"
        )
        #expect(session.displayName == "foo")
    }
}
