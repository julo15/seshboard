import Combine
import Foundation
import SeshboardCore

@MainActor
public final class SessionListViewModel: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var error: String?

    private let database: SeshboardDatabase
    private let refreshInterval: TimeInterval
    private var timer: Timer?

    public init(database: SeshboardDatabase, refreshInterval: TimeInterval = 2.0) {
        self.database = database
        self.refreshInterval = refreshInterval
    }

    public func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        do {
            sessions = try database.listSessions(limit: 50)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Active sessions (idle or working), sorted most recent first.
    public var activeSessions: [Session] {
        sessions.filter { $0.isActive }
    }

    /// Recent completed/canceled/stale sessions.
    public var recentSessions: [Session] {
        sessions.filter { !$0.isActive }
    }
}
