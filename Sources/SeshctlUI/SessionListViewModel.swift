import AppKit
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
    @Published public var pendingMarkAllRead: Bool = false
    @Published public private(set) var unreadSessionIds: Set<String> = []
    @Published public private(set) var recallResults: [RecallResult] = []
    @Published public private(set) var isRecallSearching: Bool = false
    @Published public private(set) var recallUnavailable: Bool = false
    @Published public private(set) var recallGeneration: Int = 0

    private let database: SeshctlDatabase
    private let refreshInterval: TimeInterval
    private let enableGC: Bool
    private var timer: Timer?
    private var lastGC: Date = .distantPast
    private let gcInterval: TimeInterval = 60  // GC at most once per minute
    private var lastFocusedSessionId: String?
    private var lastFocusedAt: Date?
    private let focusMemoryWindow: TimeInterval
    private var recallSearchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

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
        pendingMarkAllRead = false
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
                || (session.lastReply?.lowercased().contains(query) ?? false)
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
        pendingMarkAllRead = false
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
        let count = totalResultCount
        guard count > 0 else { return }
        selectedIndex = count - 1
    }

    /// Ordered list matching the view: active first, then recent.
    public var orderedSessions: [Session] {
        activeSessions + recentSessions
    }

    /// Total number of items across all sections (filter + recall).
    public var totalResultCount: Int {
        if isSearching {
            return orderedSessions.count + recallResults.count
        }
        return orderedSessions.count
    }

    /// The currently selected recall result, if the selection is in the semantic section.
    public var selectedRecallResult: RecallResult? {
        let sessionCount = orderedSessions.count
        guard isSearching, selectedIndex >= sessionCount else { return nil }
        let recallIndex = selectedIndex - sessionCount
        guard recallIndex >= 0, recallIndex < recallResults.count else { return nil }
        return recallResults[recallIndex]
    }

    public func moveSelectionDown() {
        pendingKillSessionId = nil
        pendingMarkAllRead = false
        let count = totalResultCount
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    public func moveSelectionBy(_ delta: Int) {
        pendingKillSessionId = nil
        pendingMarkAllRead = false
        let count = totalResultCount
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
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
        debounceTask?.cancel()
        recallSearchTask?.cancel()
        recallResults = []
        isRecallSearching = false
    }

    public func appendSearchCharacter(_ char: String) {
        searchQuery.append(char)
        selectedIndex = 0
        triggerRecallSearch()
    }

    public func deleteSearchCharacter() {
        guard !searchQuery.isEmpty else {
            exitSearch()
            return
        }
        searchQuery.removeLast()
        selectedIndex = 0
        triggerRecallSearch()
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

    // MARK: - Mark all read

    public func requestMarkAllRead() {
        guard !unreadSessionIds.isEmpty else { return }
        pendingMarkAllRead = true
    }

    public func confirmMarkAllRead() {
        do {
            for id in unreadSessionIds {
                try database.markSessionRead(id: id)
            }
            unreadSessionIds.removeAll()
        } catch {
            // DB write failed; next refresh will re-sync
        }
        pendingMarkAllRead = false
    }

    public func cancelMarkAllRead() {
        pendingMarkAllRead = false
    }

    // MARK: - Recall semantic search

    /// Copy a recall result's resume command to the clipboard.
    public func copyResumeCommand(_ result: RecallResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.resumeCmd, forType: .string)
    }
    /// Find any session (active or inactive) matching a recall result's session ID.
    public func session(for result: RecallResult) -> Session? {
        sessions.first { $0.conversationId == result.sessionId }
    }

    private func triggerRecallSearch() {
        debounceTask?.cancel()
        recallSearchTask?.cancel()

        let query = searchQuery
        guard !query.isEmpty else {
            recallResults = []
            isRecallSearching = false
            return
        }

        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.executeRecallSearch(query: query)
        }
    }

    private func executeRecallSearch(query: String) {
        guard !recallUnavailable else { return }
        isRecallSearching = true
        recallResults = []

        recallSearchTask = Task { @MainActor [weak self] in
            do {
                let results = try await RecallService.search(query: query)
                guard !Task.isCancelled else { return }
                let filterIds = Set(self?.orderedSessions.compactMap(\.conversationId) ?? [])
                self?.recallResults = results.filter { !filterIds.contains($0.sessionId) }
                self?.recallGeneration += 1
                self?.isRecallSearching = false
            } catch let recallError as RecallError {
                guard !Task.isCancelled else { return }
                if case .notInstalled = recallError {
                    self?.recallUnavailable = true
                }
                self?.isRecallSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.isRecallSearching = false
            }
        }
    }
}

