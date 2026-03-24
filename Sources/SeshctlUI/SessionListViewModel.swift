import Combine
import Darwin
import Foundation
import SeshctlCore

@MainActor
public final class SessionListViewModel: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var error: String?
    @Published public var selectedIndex: Int = 0
    @Published public var isSearching: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var isNavigatingSearch: Bool = false
    @Published public var pendingKillSessionId: String?
    @Published public private(set) var unreadSessionIds: Set<String> = []

    private let database: SeshctlDatabase
    private let refreshInterval: TimeInterval
    private let enableGC: Bool
    private var timer: Timer?
    private var lastGC: Date = .distantPast
    private let gcInterval: TimeInterval = 60  // GC at most once per minute
    private var lastFocusedSessionId: String?
    private var lastFocusedAt: Date?
    private let focusMemoryWindow: TimeInterval

    public init(database: SeshctlDatabase, refreshInterval: TimeInterval = 2.0, enableGC: Bool = true, focusMemoryWindow: TimeInterval = 30) {
        self.database = database
        self.refreshInterval = refreshInterval
        self.enableGC = enableGC
        self.focusMemoryWindow = focusMemoryWindow
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
        pendingKillSessionId = nil
    }

    public func stopPolling() {
        panelDidHide()
    }

    public func refresh() {
        do {
            if enableGC {
                try database.reapStaleSessions()
            }
            if enableGC && Date().timeIntervalSince(lastGC) > gcInterval {
                try database.gc(olderThan: 30 * 24 * 3600)
                lastGC = Date()
            }
            sessions = try database.listSessions(limit: 50)
            unreadSessionIds = Set(sessions.filter { session in
                let actionable = session.status == .idle || session.status == .waiting || session.status == .completed || session.status == .canceled || session.status == .stale
                guard actionable else { return false }
                guard let lastReadAt = session.lastReadAt else { return true }
                return session.updatedAt > lastReadAt
            }.map(\.id))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sessions filtered by search query when searching.
    private var filteredSessions: [Session] {
        guard isSearching, !searchQuery.isEmpty else { return sessions }
        let query = searchQuery.lowercased()
        return sessions.filter { session in
            session.directory.lowercased().contains(query)
                || (session.gitRepoName?.lowercased().contains(query) ?? false)
                || (session.gitBranch?.lowercased().contains(query) ?? false)
                || (session.lastAsk?.lowercased().contains(query) ?? false)
                || session.tool.rawValue.lowercased().contains(query)
        }
    }

    /// Active sessions (idle or working), sorted most recent first.
    public var activeSessions: [Session] {
        filteredSessions.filter { $0.isActive }
    }

    /// Recent completed/canceled/stale sessions.
    public var recentSessions: [Session] {
        filteredSessions.filter { !$0.isActive }
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
        pendingKillSessionId = nil
        guard !sessions.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    public func moveToTop() {
        pendingKillSessionId = nil
        guard !sessions.isEmpty else { return }
        selectedIndex = 0
    }

    public func moveToBottom() {
        pendingKillSessionId = nil
        let count = orderedSessions.count
        guard count > 0 else { return }
        selectedIndex = count - 1
    }

    /// Ordered list matching the view: active first, then recent.
    public var orderedSessions: [Session] {
        activeSessions + recentSessions
    }

    public func moveSelectionDown() {
        pendingKillSessionId = nil
        let count = orderedSessions.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    public func rememberFocusedSession(_ session: Session) {
        lastFocusedSessionId = session.id
        lastFocusedAt = Date()
    }

    public func markSessionRead(_ session: Session) {
        do {
            try database.markSessionRead(id: session.id)
            unreadSessionIds.remove(session.id)
        } catch {
            // DB write failed; leave unread state unchanged so next refresh re-syncs
        }
    }

    public func resetSelection() {
        if let id = lastFocusedSessionId,
           let focusedAt = lastFocusedAt,
           Date().timeIntervalSince(focusedAt) < focusMemoryWindow {
            let ordered = orderedSessions
            if let index = ordered.firstIndex(where: { $0.id == id && $0.isActive }) {
                selectedIndex = index
                return
            }
        }
        selectedIndex = 0
    }

    public func enterSearch() {
        isSearching = true
        searchQuery = ""
        selectedIndex = 0
    }

    public func exitSearch() {
        isSearching = false
        searchQuery = ""
        isNavigatingSearch = false
        selectedIndex = 0
    }

    public func appendSearchCharacter(_ char: String) {
        searchQuery.append(char)
        selectedIndex = 0
    }

    public func deleteSearchCharacter() {
        guard !searchQuery.isEmpty else {
            exitSearch()
            return
        }
        searchQuery.removeLast()
        selectedIndex = 0
    }

    // MARK: - Kill process

    public func requestKill() {
        guard let session = selectedSession, session.isActive, session.pid != nil else { return }
        pendingKillSessionId = session.id
    }

    public func confirmKill() {
        guard let killId = pendingKillSessionId,
              let session = orderedSessions.first(where: { $0.id == killId }),
              session.isActive,
              let pid = session.pid else {
            pendingKillSessionId = nil
            return
        }
        kill(Int32(pid), SIGTERM)
        pendingKillSessionId = nil
        refresh()
    }

    public func cancelKill() {
        pendingKillSessionId = nil
    }
}
