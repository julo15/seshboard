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
                            ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { index, session in
                                let isActive = session.isActive
                                let isSelected = index == viewModel.selectedIndex

                                SessionRowView(session: session, hostApp: hostAppResolver.resolve(session: session))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedIndex = index
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
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        guard newIndex >= 0, newIndex < viewModel.sessions.count else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(viewModel.sessions[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 400)
    }
}
