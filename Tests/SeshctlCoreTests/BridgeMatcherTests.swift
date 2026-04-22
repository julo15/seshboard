import Foundation
import Testing

@testable import SeshctlCore

private enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func local(
        id: String,
        transcriptPath: String? = nil,
        status: SessionStatus = .idle
    ) -> Session {
        Session(
            id: id,
            conversationId: nil,
            tool: .claude,
            directory: "/x/foo",
            launchDirectory: nil,
            hostWorkspaceFolder: nil,
            lastAsk: nil,
            lastReply: nil,
            status: status,
            pid: 1234,
            hostAppBundleId: nil,
            hostAppName: nil,
            windowId: nil,
            transcriptPath: transcriptPath,
            gitRepoName: nil,
            gitBranch: "main",
            launchArgs: nil,
            startedAt: t0,
            updatedAt: t0,
            lastReadAt: nil
        )
    }

    static func remote(
        id: String,
        environmentKind: String = "bridge"
    ) -> RemoteClaudeCodeSession {
        RemoteClaudeCodeSession(
            id: id,
            title: "t",
            model: "claude-opus-4-7",
            repoUrl: "https://github.com/x/foo",
            branches: ["main"],
            status: "active",
            workerStatus: "idle",
            connectionStatus: "connected",
            lastEventAt: t0,
            createdAt: t0,
            unread: false,
            lastReadAt: nil,
            environmentKind: environmentKind
        )
    }
}

@Suite("BridgeMatcher")
struct BridgeMatcherTests {

    @Test("pairs a local whose transcript declares a cse_id to the matching bridge remote")
    func happyPath() {
        let local = Fixture.local(id: "L1")
        let remote = Fixture.remote(id: "cse_ABC")
        let pairs = BridgeMatcher.match(
            locals: [local],
            remotes: [remote],
            bridgedRemoteId: { _ in "cse_ABC" }
        )
        #expect(pairs == [BridgeMatcher.Pair(localId: "L1", remoteId: "cse_ABC")])
    }

    @Test("no pair when transcript declares a cse_id absent from the remote list")
    func cseNotInRemotes() {
        let local = Fixture.local(id: "L1")
        let remote = Fixture.remote(id: "cse_OTHER")
        let pairs = BridgeMatcher.match(
            locals: [local],
            remotes: [remote],
            bridgedRemoteId: { _ in "cse_MISSING" }
        )
        #expect(pairs.isEmpty)
    }

    @Test("no pair when the remote with matching id is not environment_kind=bridge")
    func remoteNotBridge() {
        let local = Fixture.local(id: "L1")
        let remote = Fixture.remote(id: "cse_ABC", environmentKind: "") // native cloud
        let pairs = BridgeMatcher.match(
            locals: [local],
            remotes: [remote],
            bridgedRemoteId: { _ in "cse_ABC" }
        )
        #expect(pairs.isEmpty)
    }

    @Test("no pair when local status is terminal (.completed)")
    func terminalLocalStatus() {
        let local = Fixture.local(id: "L1", status: .completed)
        let remote = Fixture.remote(id: "cse_ABC")
        let pairs = BridgeMatcher.match(
            locals: [local],
            remotes: [remote],
            bridgedRemoteId: { _ in "cse_ABC" }
        )
        #expect(pairs.isEmpty)
    }

    @Test("no pair when transcript scan returns nil (never bridged)")
    func noTranscriptSignal() {
        let local = Fixture.local(id: "L1")
        let remote = Fixture.remote(id: "cse_ABC")
        let pairs = BridgeMatcher.match(
            locals: [local],
            remotes: [remote],
            bridgedRemoteId: { _ in nil }
        )
        #expect(pairs.isEmpty)
    }

    @Test("multiple locals on the same folder — only the actually-bridged one pairs")
    func multipleLocalsOneBridged() {
        let bridged = Fixture.local(id: "BRIDGED")
        let sibling = Fixture.local(id: "SIBLING")
        let remote = Fixture.remote(id: "cse_ABC")
        let pairs = BridgeMatcher.match(
            locals: [sibling, bridged],
            remotes: [remote],
            bridgedRemoteId: { local in
                local.id == "BRIDGED" ? "cse_ABC" : nil
            }
        )
        #expect(pairs == [BridgeMatcher.Pair(localId: "BRIDGED", remoteId: "cse_ABC")])
    }

    @Test("two locals declare the same cse_id — first seen wins, second is unpaired")
    func duplicateClaimsOnSameRemote() {
        let l1 = Fixture.local(id: "L1")
        let l2 = Fixture.local(id: "L2")
        let remote = Fixture.remote(id: "cse_ABC")
        let pairs = BridgeMatcher.match(
            locals: [l1, l2],
            remotes: [remote],
            bridgedRemoteId: { _ in "cse_ABC" }
        )
        #expect(pairs == [BridgeMatcher.Pair(localId: "L1", remoteId: "cse_ABC")])
    }

    @Test("multiple bridged remotes — each pairs with the local that declares its id")
    func multiplePairs() {
        let lA = Fixture.local(id: "LA")
        let lB = Fixture.local(id: "LB")
        let rA = Fixture.remote(id: "cse_A")
        let rB = Fixture.remote(id: "cse_B")
        let pairs = BridgeMatcher.match(
            locals: [lA, lB],
            remotes: [rA, rB],
            bridgedRemoteId: { local in
                local.id == "LA" ? "cse_A" : "cse_B"
            }
        )
        #expect(Set(pairs) == Set([
            BridgeMatcher.Pair(localId: "LA", remoteId: "cse_A"),
            BridgeMatcher.Pair(localId: "LB", remoteId: "cse_B"),
        ]))
    }
}
