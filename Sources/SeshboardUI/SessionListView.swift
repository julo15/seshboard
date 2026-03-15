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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !viewModel.activeSessions.isEmpty {
                            sectionHeader("Active")
                            ForEach(viewModel.activeSessions) { session in
                                sessionRow(session, isActive: true)
                            }
                        }

                        if !viewModel.recentSessions.isEmpty {
                            sectionHeader("Recent")
                            ForEach(viewModel.recentSessions) { session in
                                sessionRow(session, isActive: false)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 360, height: 400)
    }

    private func sessionRow(_ session: Session, isActive: Bool) -> some View {
        SessionRowView(session: session, hostApp: hostAppResolver.resolve(pid: session.pid))
            .contentShape(Rectangle())
            .onTapGesture {
                onSessionTap?(session)
            }
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.05))
                    : nil
            )
            .opacity(isActive ? 1.0 : 0.7)
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
