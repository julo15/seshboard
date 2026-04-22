import SwiftUI

import SeshctlCore

/// One-line banner strip that sits above the session list when the cloud
/// connection needs user attention. Observes a `ClaudeCodeConnectionStore`
/// and renders state-dependent content — hidden entirely when connected or
/// in a transient-error state (the plan routes transient errors to inline
/// treatment on cloud rows instead of a global banner).
public struct SignInBanner: View {
    @ObservedObject public var store: ClaudeCodeConnectionStore

    public init(store: ClaudeCodeConnectionStore) {
        self.store = store
    }

    public var body: some View {
        switch Self.presentation(for: store.state) {
        case .hidden:
            EmptyView()
        case .connect:
            bannerBody(
                title: "Connect to Claude Code",
                tint: Color.accentColor,
                button: ("Connect", { store.presentSignIn() }),
                spinner: false
            )
        case .connecting:
            bannerBody(
                title: "Signing in to Claude Code…",
                tint: Color.accentColor,
                button: nil,
                spinner: true
            )
        case .reconnect:
            bannerBody(
                title: "Claude Code sign-in expired",
                tint: Color.orange,
                button: ("Reconnect", { store.presentSignIn() }),
                spinner: false
            )
        }
    }

    // MARK: - Body helper

    @ViewBuilder
    private func bannerBody(
        title: String,
        tint: Color,
        button: (String, () -> Void)?,
        spinner: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.footnote, design: .monospaced, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if spinner {
                ProgressView()
                    .controlSize(.small)
            }
            if let (label, action) = button {
                Button(label, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(tint.opacity(0.12))
    }

    // MARK: - Pure presentation mapping

    /// Which banner (if any) to show for a given connection-store state.
    /// Pure so the mapping is directly testable without mounting SwiftUI.
    public enum BannerPresentation: Equatable, Sendable {
        /// Banner is not rendered.
        case hidden
        /// "Connect to Claude Code" + Connect button.
        case connect
        /// "Signing in to Claude Code…" (spinner, no button).
        case connecting
        /// "Claude Code sign-in expired" + Reconnect button.
        case reconnect
    }

    /// Map a connection-store state to the banner presentation. Transient
    /// errors and the connected states intentionally return `.hidden` — the
    /// plan routes those to inline treatment / the settings popover instead
    /// of a global banner.
    ///
    /// `nonisolated` so tests can call it without hopping to the main actor
    /// (mirrors `ClaudeCodeConnectionStore.stateForFetchResult`).
    public nonisolated static func presentation(
        for state: ClaudeCodeConnectionStore.State
    ) -> BannerPresentation {
        switch state {
        case .notConnected:
            return .connect
        case .connecting:
            return .connecting
        case .connected:
            return .hidden
        case .authExpired:
            return .reconnect
        case .transientError:
            return .hidden
        }
    }
}
