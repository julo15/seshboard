import SwiftUI
import SeshboardCore

public struct SessionListView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @StateObject private var hostAppResolver = HostAppResolver()
    var onSessionTap: ((Session) -> Void)?

    public init(viewModel: SessionListViewModel, onSessionTap: ((Session) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSessionTap = onSessionTap
    }

    /// Flat ordered list: active first, then recent. This is what keyboard nav indexes into.
    private var orderedSessions: [Session] {
        viewModel.activeSessions + viewModel.recentSessions
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seshboard")
                    .font(.system(.headline, design: .monospaced))
                Spacer()
                Text("\(viewModel.activeSessions.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let active = viewModel.activeSessions
                            let recent = viewModel.recentSessions

                            if !active.isEmpty {
                                sectionHeader("Active")
                                ForEach(Array(active.enumerated()), id: \.element.id) { i, session in
                                    sessionRow(session, flatIndex: i, isActive: true)
                                }
                            }

                            if !recent.isEmpty {
                                sectionHeader("Recent")
                                ForEach(Array(recent.enumerated()), id: \.element.id) { i, session in
                                    sessionRow(session, flatIndex: active.count + i, isActive: false)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        let ordered = orderedSessions
                        guard newIndex >= 0, newIndex < ordered.count else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(ordered[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 400)
    }

    private func sessionRow(_ session: Session, flatIndex: Int, isActive: Bool) -> some View {
        let isSelected = flatIndex == viewModel.selectedIndex

        return SessionRowView(session: session, hostApp: hostAppResolver.resolve(session: session))
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectedIndex = flatIndex
                onSessionTap?(session)
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
            .id(session.id)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
