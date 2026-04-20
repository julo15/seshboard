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
        let ordered = viewModel.treeOrderedRows

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.treeGroups) { group in
                        GroupHeaderView(name: group.name, count: group.rows.count)
                            .id(group.id)

                        ForEach(group.rows, id: \.id) { row in
                            let index = ordered.firstIndex(where: { $0.id == row.id }) ?? -1
                            let isSelected = index >= 0 && index == viewModel.selectedIndex
                            let isActive = row.isActive

                            rowView(for: row)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if index >= 0 {
                                        viewModel.selectedIndex = index
                                    }
                                    if case .local(let session) = row {
                                        onSessionTap?(session)
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected
                                            ? Color.accentColor.opacity(0.2)
                                            : isActive
                                                ? Color.accentColor.opacity(0.05)
                                                : Color.clear)
                                )
                                .opacity(isActive || isSelected ? 1.0 : 0.7)
                                .id(rowViewIdentity(for: row))
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

    /// Renders a tree-view row for a `DisplayRow`. Local rows use the
    /// existing `SessionRowView`; remote rows render a TEMPORARY placeholder
    /// until `RemoteClaudeCodeRowView` lands in Step 6.
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
}

private struct GroupHeaderView: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
