import Combine
import Foundation
import SeshboardCore

@MainActor
public final class SessionListViewModel: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var error: String?
    @Published public var selectedIndex: Int = 0

    private let database: SeshboardDatabase
    private let refreshInterval: TimeInterval
    private let enableGC: Bool
    private var timer: Timer?
    private var lastGC: Date = .distantPast
    private let gcInterval: TimeInterval = 60  // GC at most once per minute

    public init(database: SeshboardDatabase, refreshInterval: TimeInterval = 2.0, enableGC: Bool = true) {
        self.database = database
        self.refreshInterval = refreshInterval
        self.enableGC = enableGC
    }

    public func startPolling() {
        // Don't start a timer — polling is driven by show/hide
    }

    /// Call when the panel becomes visible. Refreshes immediately and starts polling.
    public func panelDidShow() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// Call when the panel is hidden. Stops polling.
    public func panelDidHide() {
        timer?.invalidate()
        timer = nil
    }

    public func stopPolling() {
        panelDidHide()
    }

    public func refresh() {
        do {
            if enableGC && Date().timeIntervalSince(lastGC) > gcInterval {
                try database.gc(olderThan: 30 * 24 * 3600)
                lastGC = Date()
            }
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

    /// The currently selected session, if any.
    public var selectedSession: Session? {
        let ordered = orderedSessions
        guard !ordered.isEmpty, selectedIndex >= 0, selectedIndex < ordered.count else {
            return nil
        }
        return ordered[selectedIndex]
    }

    public func moveSelectionUp() {
        guard !sessions.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    /// Ordered list matching the view: active first, then recent.
    public var orderedSessions: [Session] {
        activeSessions + recentSessions
    }

    public func moveSelectionDown() {
        let count = orderedSessions.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    public func resetSelection() {
        selectedIndex = 0
    }
}
