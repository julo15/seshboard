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

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seshboard")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(viewModel.activeSessions.count) active")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                                    hostApp: hostAppResolver.resolve(session: session)
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
                                .opacity(session.isActive || isSelected ? 1.0 : 0.7)
                                .id("\(session.id)-\(session.status.rawValue)")
                            }

                            if activeCount == 0 && !ordered.isEmpty {
                                sectionHeader("Recent")
                                    .padding(.top, -4) // adjust since ForEach won't insert it
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        guard newIndex >= 0, newIndex < ordered.count else { return }
                        let session = ordered[newIndex]
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("\(session.id)-\(session.status.rawValue)", anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 720, height: 560)
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
