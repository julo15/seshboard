import SwiftUI
import SeshctlCore

public struct SessionDetailView: View {
    @ObservedObject var viewModel: SessionDetailViewModel

    public init(viewModel: SessionDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(primaryName)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                if let branch = viewModel.session.gitBranch {
                    Text("·")
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(branch)
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(Session.branchColor(for: branch))
                }
                Spacer()
                Text(viewModel.session.tool.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                Spacer()
            } else if let error = viewModel.error {
                Spacer()
                Text(error)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            } else if viewModel.turns.isEmpty {
                Spacer()
                Text("No messages")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 1).id("top-anchor")

                            let turns = viewModel.turns
                            ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                                let prevIsAssistant = index > 0 && isAssistant(turns[index - 1])
                                let currentIsAssistant = isAssistant(turn)
                                let showHeader = !(currentIsAssistant && prevIsAssistant)

                                TurnView(turn: turn, showHeader: showHeader)
                                    .id(turn.id)

                                // Only show divider between different roles
                                if showHeader || index == turns.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }

                            Color.clear.frame(height: 1).id("bottom-anchor")
                        }
                    }
                    .onAppear {
                        // Start at bottom
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onChange(of: viewModel.scrollCommand) { command in
                        guard let command else { return }
                        handleScroll(command: command, proxy: proxy)
                        viewModel.scrollCommand = nil
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("q/esc back")
                Spacer()
                Text("j/k scroll · ^f/^b page · G/gg end/top")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(width: 720, height: 560)
    }

    private func isAssistant(_ turn: ConversationTurn) -> Bool {
        if case .assistantMessage = turn { return true }
        return false
    }

    private var primaryName: String {
        viewModel.session.gitRepoName ?? (viewModel.session.directory as NSString).lastPathComponent
    }

    private func handleScroll(command: SessionDetailViewModel.ScrollCommand, proxy: ScrollViewProxy) {
        // For top/bottom we can use anchors directly.
        // For line/page scrolling, we find the NSScrollView and adjust pixel offsets.
        switch command {
        case .top:
            withAnimation(.easeOut(duration: 0.05)) {
                proxy.scrollTo("top-anchor", anchor: .top)
            }
        case .bottom:
            withAnimation(.easeOut(duration: 0.05)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        case .lineDown, .lineUp, .halfPageDown, .halfPageUp, .pageDown, .pageUp:
            scrollByPixels(command: command)
        }
    }

    /// Access the underlying NSScrollView and scroll by pixel offset.
    private func scrollByPixels(command: SessionDetailViewModel.ScrollCommand) {
        guard let scrollView = findScrollView() else { return }
        let clipView = scrollView.contentView
        let visibleHeight = clipView.bounds.height
        let currentY = clipView.bounds.origin.y
        let maxY = (scrollView.documentView?.frame.height ?? 0) - visibleHeight

        let delta: CGFloat
        switch command {
        case .lineDown: delta = 20
        case .lineUp: delta = -20
        case .halfPageDown: delta = visibleHeight / 2
        case .halfPageUp: delta = -(visibleHeight / 2)
        case .pageDown: delta = visibleHeight
        case .pageUp: delta = -visibleHeight
        default: return
        }

        let newY = min(max(currentY + delta, 0), max(maxY, 0))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: newY))
        }
    }

    /// Walk the NSView hierarchy to find the NSScrollView backing SwiftUI's ScrollView.
    private func findScrollView() -> NSScrollView? {
        guard let window = NSApp.keyWindow else { return nil }
        return findScrollViewIn(window.contentView)
    }

    private func findScrollViewIn(_ view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let sv = view as? NSScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollViewIn(sub) { return found }
        }
        return nil
    }
}
