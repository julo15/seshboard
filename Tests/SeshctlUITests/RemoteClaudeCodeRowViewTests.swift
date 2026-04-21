import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

// MARK: - Status tests

@Suite("RemoteClaudeCodeRowView.status")
struct RemoteClaudeCodeRowViewStatusTests {

    @Test("stale wins when auth-expired, regardless of worker state")
    func staleBeatsEverything() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "running",
            connectionStatus: "connected",
            isStale: true
        )
        #expect(s == .stale)
    }

    @Test("running worker is .running")
    func runningWorker() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "running",
            connectionStatus: "connected",
            isStale: false
        )
        #expect(s == .running)
    }

    @Test("waiting worker is .waiting")
    func waitingWorker() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "waiting",
            connectionStatus: "connected",
            isStale: false
        )
        #expect(s == .waiting)
    }

    @Test("requires_action worker is .waiting (pending user input)")
    func requiresActionWorker() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "requires_action",
            connectionStatus: "connected",
            isStale: false
        )
        #expect(s == .waiting)
    }

    @Test("idle + connected is .idle")
    func idleConnected() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "idle",
            connectionStatus: "connected",
            isStale: false
        )
        #expect(s == .idle)
    }

    @Test("disconnected connection is .offline")
    func disconnectedConnection() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "idle",
            connectionStatus: "disconnected",
            isStale: false
        )
        #expect(s == .offline)
    }

    @Test("disconnected worker is .offline")
    func disconnectedWorker() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "disconnected",
            connectionStatus: "connected",
            isStale: false
        )
        #expect(s == .offline)
    }

    @Test("stale beats waiting")
    func staleBeatsWaiting() {
        let s = RemoteClaudeCodeRowView.status(
            workerStatus: "waiting",
            connectionStatus: "connected",
            isStale: true
        )
        #expect(s == .stale)
    }
}

// MARK: - Color tests

@Suite("RemoteClaudeCodeRowView.color")
struct RemoteClaudeCodeRowViewColorTests {

    @Test("waiting is blue (matches local .waiting vocabulary)")
    func waitingIsBlue() {
        #expect(RemoteClaudeCodeRowView.color(for: .waiting) == .blue)
    }

    @Test("running is orange")
    func runningIsOrange() {
        #expect(RemoteClaudeCodeRowView.color(for: .running) == .orange)
    }

    @Test("idle is green")
    func idleIsGreen() {
        #expect(RemoteClaudeCodeRowView.color(for: .idle) == .green)
    }

    @Test("offline is gray")
    func offlineIsGray() {
        #expect(RemoteClaudeCodeRowView.color(for: .offline) == .gray)
    }
}
