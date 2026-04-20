import SwiftUI
import SeshctlCore

public struct SessionListView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @ObservedObject var connectionStore: ClaudeCodeConnectionStore
    @StateObject private var hostAppResolver = HostAppResolver()
    @State private var showingSettings = false
    var onSessionTap: ((Session) -> Void)?
    var onOpenDetail: ((Session) -> Void)?
    var onOpenRecallDetail: ((RecallResult, Session?) -> Void)?

    public init(
        viewModel: SessionListViewModel,
        connectionStore: ClaudeCodeConnectionStore,
        onSessionTap: ((Session) -> Void)? = nil,
        onOpenDetail: ((Session) -> Void)? = nil,
        onOpenRecallDetail: ((RecallResult, Session?) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.connectionStore = connectionStore
        self.onSessionTap = onSessionTap
        self.onOpenDetail = onOpenDetail
        self.onOpenRecallDetail = onOpenRecallDetail
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Seshctl")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(viewModel.activeRows.count) active")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.title3))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsPopover(store: connectionStore)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if viewModel.isSearching {
                SearchBar(query: viewModel.searchQuery, isActive: !viewModel.isNavigatingSearch) {
                    Text(viewModel.isNavigatingSearch
                         ? "shift-tab to edit · esc to close"
                         : "tab to navigate · esc to close")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            if let error = viewModel.error {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding()
            } else if viewModel.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("No sessions")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Start a Claude/Gemini/Codex session to see it here.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else if viewModel.isTreeMode && !viewModel.isSearching {
                SessionTreeView(
                    viewModel: viewModel,
                    onSessionTap: onSessionTap,
                    onOpenDetail: onOpenDetail
                )
            } else {
                let ordered = viewModel.orderedRows
                let activeCount = viewModel.activeRows.count

                // activeRows is sorted by sortTimestamp DESC so buckets appear
                // in calendar-day order.
                let now = Date()
                let activeBuckets: [SessionAgeDisplay.AgeBucket] = (0..<activeCount).map { idx in
                    SessionAgeDisplay(timestamp: ordered[idx].sortTimestamp, now: now).bucket
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, row in
                                if index < activeCount {
                                    let bucket = activeBuckets[index]
                                    let isFirstOfBucket = index == 0 || activeBuckets[index - 1] != bucket
                                    if isFirstOfBucket {
                                        // Bucket headers only appear above active sessions; closed sessions render under the "Recent" header below.
                                        sectionHeader(bucket.displayName)
                                    }
                                } else if index == activeCount && activeCount > 0 {
                                    sectionHeader("Recent")
                                }

                                let isSelected = index == viewModel.selectedIndex
                                let isRowActive = row.isActive

                                rowView(for: row)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
                                        if case .local(let session) = row {
                                            onSessionTap?(session)
                                        }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected
                                                ? Color.accentColor.opacity(0.2)
                                                : isRowActive
                                                    ? Color.accentColor.opacity(0.05)
                                                    : Color.clear)
                                    )
                                    .opacity(rowOpacity(isActive: isRowActive, isSelected: isSelected))
                                    .id(rowViewIdentity(for: row))
                            }

                            if activeCount == 0 && !ordered.isEmpty {
                                sectionHeader("Recent")
                                    .padding(.top, -4) // adjust since ForEach won't insert it
                            }

                            // Semantic search section
                            if viewModel.isSearching {
                                if viewModel.isRecallSearching {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Group {
                                            if let total = viewModel.recallIndexingTotal {
                                                if let done = viewModel.recallIndexingDone, done > 0 {
                                                    Text("Indexing \(done)/\(total) entries...")
                                                } else {
                                                    Text("Indexing \(total) entries...")
                                                }
                                            } else {
                                                Text("Searching...")
                                            }
                                        }
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }

                                if !viewModel.recallResults.isEmpty {
                                    sectionHeader("Semantic")

                                    ForEach(Array(viewModel.recallResults.enumerated()), id: \.element.id) { recallIndex, result in
                                        let globalIndex = ordered.count + recallIndex
                                        let isSelected = globalIndex == viewModel.selectedIndex
                                        let matchedSession = viewModel.session(for: result)

                                        RecallResultRowView(
                                            result: result,
                                            isActive: matchedSession?.isActive ?? false,
                                            hostApp: matchedSession.map { hostAppResolver.resolve(session: $0) },
                                            searchQuery: viewModel.searchQuery,
                                            onDetail: onOpenRecallDetail.map { handler in
                                                {
                                                    if let session = matchedSession {
                                                        viewModel.markSessionRead(session)
                                                    }
                                                    handler(result, matchedSession)
                                                }
                                            }
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.selectedIndex = globalIndex
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected
                                                    ? Color.accentColor.opacity(0.2)
                                                    : Color.clear)
                                        )
                                        .opacity(isSelected ? 0.9 : 0.6)
                                        .id("recall-\(viewModel.recallGeneration)-\(recallIndex)")
                                    }
                                }

                                if viewModel.recallUnavailable {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundStyle(.tertiary)
                                        Text("Install recall for semantic search")
                                            .font(.system(.footnote, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .followSelectionScroll(
                        ordered: ordered,
                        selectedIndex: viewModel.selectedIndex,
                        proxy: proxy
                    )
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        guard viewModel.isSearching, newIndex >= ordered.count else { return }
                        let recallIndex = newIndex - ordered.count
                        if recallIndex >= 0 && recallIndex < viewModel.recallResults.count {
                            withAnimation(.easeOut(duration: 0.02)) {
                                proxy.scrollTo("recall-\(viewModel.recallGeneration)-\(recallIndex)", anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if viewModel.pendingKillSessionId != nil {
                    Text("kill process? y/n")
                        .foregroundStyle(.red)
                } else if viewModel.pendingMarkAllRead {
                    Text("mark all as read? y/n")
                        .foregroundStyle(.orange)
                } else {
                    Text("enter/e focus")
                    Spacer()
                    Text("x kill · j/k/tab move · \(viewModel.isTreeMode ? "h/l group · " : "")o detail · u mark read · U mark all read · \(viewModel.isTreeMode ? "v list" : "v tree") · / search · q close")
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Renders the row content for a `DisplayRow`. Local rows use the
    /// existing `SessionRowView`. Remote rows currently render a TEMPORARY
    /// placeholder — the real `RemoteClaudeCodeRowView` lands in Step 6.
    @ViewBuilder
    private func rowView(for row: DisplayRow) -> some View {
        switch row {
        case .local(let session):
            SessionRowView(
                session: session,
                hostApp: hostAppResolver.resolve(session: session),
                isUnread: viewModel.unreadSessionIds.contains(session.id),
                onDetail: onOpenDetail.map { handler in
                    {
                        viewModel.markSessionRead(session)
                        handler(session)
                    }
                }
            )
        case .remote(let remote):
            // Placeholder — replaced by `RemoteClaudeCodeRowView` in Step 6.
            HStack {
                Text(remote.title)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text("claude.ai")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func rowOpacity(isActive: Bool, isSelected: Bool) -> Double {
        let searchTyping = viewModel.isSearching && !viewModel.isNavigatingSearch
        if searchTyping {
            return isSelected ? 0.8 : 0.5
        }
        return isActive || isSelected ? 1.0 : 0.7
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
