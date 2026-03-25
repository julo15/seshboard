import SwiftUI
import SeshctlCore

public struct SessionListView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @StateObject private var hostAppResolver = HostAppResolver()
    var onSessionTap: ((Session) -> Void)?
    var onOpenDetail: ((Session) -> Void)?

    public init(viewModel: SessionListViewModel, onSessionTap: ((Session) -> Void)? = nil, onOpenDetail: ((Session) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSessionTap = onSessionTap
        self.onOpenDetail = onOpenDetail
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seshctl")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(viewModel.activeSessions.count) active")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if viewModel.isSearching {
                HStack(spacing: 0) {
                    Text("/" + viewModel.searchQuery)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(viewModel.isNavigatingSearch ? .secondary : .primary)
                    if !viewModel.isNavigatingSearch {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 1, height: 16)
                            .opacity(0.8)
                    }
                    Spacer()
                    Text(viewModel.isNavigatingSearch
                         ? "shift-tab to edit · esc to close"
                         : "tab to navigate · esc to close")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.06))
            }

            Divider()

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            } else if viewModel.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("No sessions")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Start a Claude/Gemini/Codex session to see it here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                let ordered = viewModel.orderedSessions
                let activeCount = viewModel.activeSessions.count

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if activeCount > 0 {
                                sectionHeader("Active")
                            }

                            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, session in
                                if index == activeCount && activeCount > 0 {
                                    sectionHeader("Recent")
                                }

                                let isSelected = index == viewModel.selectedIndex

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
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    onSessionTap?(session)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected
                                            ? Color.accentColor.opacity(0.2)
                                            : session.isActive
                                                ? Color.accentColor.opacity(0.05)
                                                : Color.clear)
                                )
                                .opacity(rowOpacity(isActive: session.isActive, isSelected: isSelected))
                                .id("\(session.id)-\(session.status.rawValue)")
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
                                        Text("Searching...")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }

                                if !viewModel.recallResults.isEmpty {
                                    sectionHeader("Semantic")

                                    ForEach(Array(viewModel.recallResults.enumerated()), id: \.offset) { recallIndex, result in
                                        let globalIndex = ordered.count + recallIndex
                                        let isSelected = globalIndex == viewModel.selectedIndex
                                        let hasMatch = viewModel.matchingSession(for: result) != nil

                                        RecallResultRowView(
                                            result: result,
                                            hasMatchingSession: hasMatch
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
                                        .id("recall-\(recallIndex)")
                                    }
                                }

                                if viewModel.recallUnavailable {
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundStyle(.tertiary)
                                        Text("Install recall for semantic search")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < ordered.count {
                            let session = ordered[newIndex]
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("\(session.id)-\(session.status.rawValue)", anchor: .center)
                            }
                        } else if viewModel.isSearching {
                            let recallIndex = newIndex - ordered.count
                            if recallIndex >= 0 && recallIndex < viewModel.recallResults.count {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo("recall-\(recallIndex)", anchor: .center)
                                }
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
                    Text("x kill · j/k/tab move · o detail · u mark read · U mark all read · / search · q close")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
