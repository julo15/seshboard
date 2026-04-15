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
    @Published public private(set) var recallIndexingDone: Int?
    @Published public private(set) var recallIndexingTotal: Int?
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
    private let defaults: UserDefaults

    private static let isTreeModeDefaultsKey = "seshctl.isTreeMode"

    /// Whether the seshboard is rendering the repo-grouped tree view.
    /// Not `@AppStorage` — `@AppStorage` is a `DynamicProperty` that does not
    /// fire `objectWillChange` inside an `ObservableObject`, so views bound to
    /// the viewmodel would not re-render on toggle. We store manually and
    /// write-through to the injected `UserDefaults` in `didSet`.
    @Published public var isTreeMode: Bool {
        didSet {
            defaults.set(isTreeMode, forKey: Self.isTreeModeDefaultsKey)
        }
    }

    public init(database: SeshctlDatabase, refreshInterval: TimeInterval = 2.0, enableGC: Bool = true, focusMemoryWindow: TimeInterval = 30, defaults: UserDefaults = .standard) {
        self.database = database
        self.refreshInterval = refreshInterval
        self.enableGC = enableGC
        self.focusMemoryWindow = focusMemoryWindow
        self.defaults = defaults
        self.isTreeMode = defaults.bool(forKey: Self.isTreeModeDefaultsKey)
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
        // Guard on the navigable ordering, not `sessions`. When the current
        // ordering is empty (e.g., filtered search results), preserve the
        // `selectedIndex = -1` empty-selection sentinel instead of clobbering
        // it to 0.
        guard totalResultCount > 0 else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    public func moveToTop() {
        pendingKillSessionId = nil
        guard totalResultCount > 0 else { return }
        selectedIndex = 0
    }

    public func moveToBottom() {
        pendingKillSessionId = nil
        let count = totalResultCount
        guard count > 0 else { return }
        selectedIndex = count - 1
    }

    /// A group of active sessions sharing a `(primaryName, isRepo)` key.
    /// Rendered as a header row followed by its sessions in tree mode.
    public struct SessionGroup: Equatable, Identifiable {
        public let name: String
        public let isRepo: Bool
        public let sessions: [Session]

        /// Stable identifier combining name and repo-backed flag. Matches the
        /// prior file-scope `groupID` extension so `.id(...)` scroll targets
        /// keep working.
        public var id: String { "group-\(name)-\(isRepo)" }
    }

    /// Active sessions bucketed by `(primaryName, gitRepoName != nil)`.
    /// Groups sorted alphabetically case-insensitive by name; ties broken with
    /// repo-backed groups first. Sessions inside sorted by `updatedAt` desc.
    public var treeGroups: [SessionGroup] {
        struct Key: Hashable {
            let name: String
            let isRepo: Bool
        }
        var buckets: [Key: [Session]] = [:]
        for session in activeSessions {
            let key = Key(name: session.primaryName, isRepo: session.gitRepoName != nil)
            buckets[key, default: []].append(session)
        }
        let keys = buckets.keys.sorted { lhs, rhs in
            let lname = lhs.name.lowercased()
            let rname = rhs.name.lowercased()
            if lname != rname { return lname < rname }
            // Tie-break: repo-backed groups come first.
            if lhs.isRepo != rhs.isRepo { return lhs.isRepo && !rhs.isRepo }
            return false
        }
        return keys.map { key in
            let sorted = (buckets[key] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            return SessionGroup(name: key.name, isRepo: key.isRepo, sessions: sorted)
        }
    }

    /// Flat session sequence in group/session order. Header rows are NOT
    /// included — `selectedIndex` indexes this sequence in tree mode.
    public var treeOrderedSessions: [Session] {
        treeGroups.flatMap(\.sessions)
    }

    /// Ordered list matching the view. Mode-aware: list mode is active+recent,
    /// tree mode is `treeOrderedSessions` (active-only; recents excluded).
    public var orderedSessions: [Session] {
        if isTreeMode {
            return treeOrderedSessions
        }
        return activeSessions + recentSessions
    }

    /// Toggle between list and tree mode. Remap `selectedIndex` by
    /// `session.id` so the same session stays selected across the switch.
    /// Falls back to index 0 when the prior session isn't in the new ordering,
    /// or `-1` when the new ordering is empty.
    public func toggleViewMode() {
        pendingKillSessionId = nil
        pendingMarkAllRead = false
        let prior = orderedSessions
        let priorSelected: Session? = {
            guard selectedIndex >= 0, selectedIndex < prior.count else { return nil }
            return prior[selectedIndex]
        }()
        isTreeMode.toggle()
        let next = orderedSessions
        if next.isEmpty {
            selectedIndex = -1
            return
        }
        if let target = priorSelected, let idx = next.firstIndex(where: { $0.id == target.id }) {
            selectedIndex = idx
        } else {
            selectedIndex = 0
        }
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

    /// Jump selection to the first session of the next group in tree mode.
    /// No-op in list mode, when the tree is empty, or when already at/past the
    /// last group. Preserves the `-1` sentinel when `treeOrderedSessions` is
    /// empty.
    public func jumpToNextGroup() {
        pendingKillSessionId = nil
        pendingMarkAllRead = false
        guard isTreeMode else { return }
        // Explicit no-op when there's no current selection — callers may invoke
        // this before any row has been selected, and we shouldn't silently
        // clobber the `-1` sentinel.
        guard selectedIndex >= 0 else { return }
        let ordered = treeOrderedSessions
        guard !ordered.isEmpty else { return }
        let groups = treeGroups

        // Build (groupIndex, firstFlatIndex) pairs.
        var starts: [Int] = []
        var running = 0
        for group in groups {
            starts.append(running)
            running += group.sessions.count
        }

        // Out-of-range selectedIndex (non-negative but beyond the tree) — no-op.
        guard selectedIndex < ordered.count else { return }

        // Find current group index.
        var currentGroup = 0
        for (idx, start) in starts.enumerated() {
            let end = start + groups[idx].sessions.count
            if selectedIndex >= start && selectedIndex < end {
                currentGroup = idx
                break
            }
        }
        let nextGroup = currentGroup + 1
        guard nextGroup < groups.count else { return }
        selectedIndex = starts[nextGroup]
    }

    /// Jump selection to the first session of the current group, or if already
    /// there, to the first session of the previous group. No-op at the first
    /// session of the first group, when the tree is empty, or in list mode.
    public func jumpToPreviousGroup() {
        pendingKillSessionId = nil
        pendingMarkAllRead = false
        guard isTreeMode else { return }
        // Explicit no-op when there's no current selection — preserve the `-1`
        // sentinel rather than landing on the first group.
        guard selectedIndex >= 0 else { return }
        let ordered = treeOrderedSessions
        guard !ordered.isEmpty else { return }
        let groups = treeGroups

        var starts: [Int] = []
        var running = 0
        for group in groups {
            starts.append(running)
            running += group.sessions.count
        }

        // Out-of-range selectedIndex (non-negative but beyond the tree) — no-op.
        guard selectedIndex < ordered.count else { return }

        var currentGroup = 0
        for (idx, start) in starts.enumerated() {
            let end = start + groups[idx].sessions.count
            if selectedIndex >= start && selectedIndex < end {
                currentGroup = idx
                break
            }
        }

        // Not at the first session of this group → jump to the group's first session.
        if selectedIndex > starts[currentGroup] {
            selectedIndex = starts[currentGroup]
            return
        }

        // Already at the first session of the first group → explicit no-op.
        guard currentGroup > 0 else { return }

        // Already at the first session of the current group → go to previous group.
        selectedIndex = starts[currentGroup - 1]
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
        if orderedSessions.isEmpty {
            selectedIndex = -1
            return
        }
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
        clearRecallSearchState()
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

    public func deleteSearchWord() {
        guard !searchQuery.isEmpty else {
            exitSearch()
            return
        }
        // Trim trailing whitespace, then remove back to the previous whitespace boundary
        while searchQuery.last?.isWhitespace == true { searchQuery.removeLast() }
        while let last = searchQuery.last, !last.isWhitespace { searchQuery.removeLast() }
        selectedIndex = 0
        triggerRecallSearch()
    }

    public func clearSearchQuery() {
        searchQuery = ""
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
    /// Constructs the compound form (cd + command) so the user can paste and run directly.
    public func copyResumeCommand(_ result: RecallResult) {
        let command = SessionAction.compoundShellCommand(result.resumeCmd, directory: result.project)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
    /// Find any session (active or inactive) matching a recall result's session ID.
    public func session(for result: RecallResult) -> Session? {
        sessions.first { $0.conversationId == result.sessionId }
    }

    private func clearRecallSearchState() {
        isRecallSearching = false
        recallIndexingDone = nil
        recallIndexingTotal = nil
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

    private var recallSearchGeneration: Int = 0

    private func executeRecallSearch(query: String) {
        guard !recallUnavailable else { return }
        isRecallSearching = true
        recallResults = []
        recallIndexingDone = nil
        recallIndexingTotal = nil
        recallSearchGeneration += 1
        let searchGen = recallSearchGeneration

        recallSearchTask = Task { @MainActor [weak self] in
            do {
                let onIndexing: @Sendable (Int, Int) -> Void = { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        guard self?.recallSearchGeneration == searchGen else { return }
                        self?.recallIndexingDone = done
                        self?.recallIndexingTotal = total
                    }
                }
                let response = try await RecallService.search(query: query, onIndexing: onIndexing)
                guard !Task.isCancelled else { return }
                let filterIds = Set(self?.orderedSessions.compactMap(\.conversationId) ?? [])
                self?.recallResults = response.results.filter { !filterIds.contains($0.sessionId) }
                self?.recallGeneration += 1
                self?.clearRecallSearchState()
            } catch let recallError as RecallError {
                guard !Task.isCancelled else { return }
                if case .notInstalled = recallError {
                    self?.recallUnavailable = true
                }
                self?.clearRecallSearchState()
            } catch {
                guard !Task.isCancelled else { return }
                self?.clearRecallSearchState()
            }
        }
    }
}

