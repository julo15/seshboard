import SwiftUI
import SeshctlCore

struct SessionTreeView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @StateObject private var hostAppResolver = HostAppResolver()
    var onSessionTap: ((Session) -> Void)?
    var onOpenDetail: ((Session) -> Void)?

    init(
        viewModel: SessionListViewModel,
        onSessionTap: ((Session) -> Void)? = nil,
        onOpenDetail: ((Session) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onSessionTap = onSessionTap
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        let ordered = viewModel.treeOrderedSessions

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.treeGroups) { group in
                        GroupHeaderView(name: group.name, count: group.sessions.count)
                            .id(group.id)

                        ForEach(group.sessions, id: \.id) { session in
                            let index = ordered.firstIndex(where: { $0.id == session.id }) ?? -1
                            let isSelected = index >= 0 && index == viewModel.selectedIndex

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
                                if index >= 0 {
                                    viewModel.selectedIndex = index
                                }
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
                            .opacity(session.isActive || isSelected ? 1.0 : 0.7)
                            .id("\(session.id)-\(session.status.rawValue)")
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
        }
    }
}

private struct GroupHeaderView: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
