import AppKit
import KeyboardShortcuts
import SeshctlCore
import SeshctlUI
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.s, modifiers: [.command, .shift]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var viewModel: SessionListViewModel?
    private var navigationState = NavigationState()
    private var pendingG = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Set up database and view model
        do {
            let path = NSString(
                string: "~/.local/share/seshctl/seshctl.db"
            ).expandingTildeInPath
            let db = try SeshctlDatabase(path: path)
            let vm = SessionListViewModel(database: db)
            viewModel = vm

            let nav = navigationState

            // Create panel with root view that switches between list and detail
            let rootView = RootView(
                navigationState: nav,
                listViewModel: vm,
                onSessionTap: { [weak self] session in
                    self?.focusSession(session)
                },
                onOpenDetail: { [weak nav] session in
                    nav?.openDetail(for: session)
                }
            )

            let panelRef = FloatingPanel(rootView: rootView)
            panel = panelRef

            // Keyboard navigation
            panelRef.onKeyDown = { [weak self] keyCode, chars, modifiers in
                self?.handleKey(keyCode: keyCode, chars: chars, modifiers: modifiers)
            }

            // Stop polling when panel is dismissed via click-outside
            panelRef.onDismiss = { [weak self] in
                self?.viewModel?.panelDidHide()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Seshctl failed to start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        // Register global hotkey
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }

        // Show panel on launch
        panel?.toggle()
        viewModel?.panelDidShow()
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        viewModel?.panelDidHide()
    }

    private func togglePanel() {
        panel?.toggle()
        viewModel?.exitSearch()
        if panel?.isVisible == true {
            viewModel?.panelDidShow()
            viewModel?.resetSelection()
            // Return to list when reopening
            if navigationState.screen == .detail {
                navigationState.backToList()
            }
        } else {
            viewModel?.panelDidHide()
        }
    }

    private func handleKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags) {
        guard let vm = viewModel else { return }

        // Route to detail handler if in detail view
        if let detailVM = navigationState.detailViewModel, navigationState.screen == .detail {
            handleDetailKey(keyCode: keyCode, chars: chars, modifiers: modifiers, vm: detailVM)
            return
        }

        // Cmd+Up → top, Cmd+Down → bottom (works in all modes)
        if modifiers.contains(.command) {
            if keyCode == 126 { vm.moveToTop(); return }
            if keyCode == 125 { vm.moveToBottom(); return }
        }

        if vm.isSearching {
            handleSearchKey(keyCode: keyCode, chars: chars, modifiers: modifiers, vm: vm)
        } else {
            handleNormalKey(keyCode: keyCode, chars: chars, vm: vm)
        }
    }

    private func handleNormalKey(keyCode: UInt16, chars: String?, vm: SessionListViewModel) {
        // Handle gg sequence: if g is pending and another g arrives, go to top
        if pendingG {
            pendingG = false
            if chars == "g" {
                vm.moveToTop()
                return
            }
            // Not a second g — fall through to normal handling
        }

        switch (keyCode, chars) {
        // / to enter search
        case (_, "/"):
            vm.enterSearch()
        // G (shift+g) — go to bottom
        case (_, "G"):
            vm.moveToBottom()
        // g — start gg sequence
        case (_, "g"):
            pendingG = true
        // j or Down arrow
        case (_, "j"), (125, _):
            vm.moveSelectionDown()
        // k or Up arrow
        case (_, "k"), (126, _):
            vm.moveSelectionUp()
        // Home key — go to top
        case (115, _):
            vm.moveToTop()
        // End key — go to bottom
        case (119, _):
            vm.moveToBottom()
        // o — open detail view
        case (_, "o"):
            if let session = vm.selectedSession {
                pendingG = false
                navigationState.openDetail(for: session)
            }
        // Enter or Return
        case (36, _), (76, _):
            if let session = vm.selectedSession {
                focusSession(session)
            }
        // x — kill session process
        case (_, "x"):
            if vm.pendingKillSessionId == nil {
                vm.requestKill()
            }
        // y — confirm kill
        case (_, "y"):
            if vm.pendingKillSessionId != nil {
                vm.confirmKill()
            }
        // n — cancel kill
        case (_, "n"):
            if vm.pendingKillSessionId != nil {
                vm.cancelKill()
            }
        // q or Escape — cancel kill or close panel
        case (_, "q"), (53, _):
            if vm.pendingKillSessionId != nil {
                vm.cancelKill()
            } else {
                dismissPanel()
            }
        default:
            break
        }
    }

    private func handleDetailKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags, vm: SessionDetailViewModel) {
        // Handle gg sequence
        if pendingG {
            pendingG = false
            if chars == "g" {
                vm.scrollCommand = .top
                return
            }
        }

        // Ctrl+key combos (chars from charactersIgnoringModifiers is the base letter)
        if modifiers.contains(.control), let chars {
            switch chars {
            case "d": vm.scrollCommand = .halfPageDown; return
            case "u": vm.scrollCommand = .halfPageUp; return
            case "f": vm.scrollCommand = .pageDown; return
            case "b": vm.scrollCommand = .pageUp; return
            default: break
            }
        }

        switch (keyCode, chars) {
        // q or Escape — back to list
        case (_, "q"), (53, _):
            pendingG = false
            navigationState.backToList()
        // G — jump to bottom
        case (_, "G"):
            vm.scrollCommand = .bottom
        // g — start gg sequence
        case (_, "g"):
            pendingG = true
        // j or Down arrow — line down
        case (_, "j"), (125, _):
            vm.scrollCommand = .lineDown
        // k or Up arrow — line up
        case (_, "k"), (126, _):
            vm.scrollCommand = .lineUp
        default:
            break
        }
    }

    private func handleSearchKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags, vm: SessionListViewModel) {
        switch keyCode {
        // Escape — exit search
        case 53:
            vm.exitSearch()
        // Tab — toggle navigation mode
        case 48:
            if modifiers.contains(.shift) {
                vm.isNavigatingSearch = false
            } else {
                vm.isNavigatingSearch = true
            }
        // Delete/Backspace
        case 51:
            if vm.isNavigatingSearch {
                vm.isNavigatingSearch = false
            } else {
                vm.deleteSearchCharacter()
            }
        // Enter/Return — focus selected session
        case 36, 76:
            if let session = vm.selectedSession {
                focusSession(session)
            }
        // Down arrow
        case 125:
            vm.moveSelectionDown()
        // Up arrow
        case 126:
            vm.moveSelectionUp()
        default:
            if vm.isNavigatingSearch {
                // j/k navigation while in nav mode
                if chars == "j" {
                    vm.moveSelectionDown()
                } else if chars == "k" {
                    vm.moveSelectionUp()
                }
            } else if let chars, !chars.isEmpty {
                vm.appendSearchCharacter(chars)
            }
        }
    }

    private func focusSession(_ session: Session) {
        viewModel?.rememberFocusedSession(session)
        // Hide the panel first to avoid resignKey() racing with app activation,
        // which can cause a focus flicker (target app activates → panel loses key
        // → macOS briefly refocuses another window).
        dismissPanel()
        if let pid = session.pid {
            WindowFocuser.focus(pid: pid, directory: session.directory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject var navigationState: NavigationState
    @ObservedObject var listViewModel: SessionListViewModel
    var onSessionTap: ((Session) -> Void)?
    var onOpenDetail: ((Session) -> Void)?

    var body: some View {
        Group {
            switch navigationState.screen {
            case .list:
                SessionListView(viewModel: listViewModel, onSessionTap: onSessionTap, onOpenDetail: onOpenDetail)
            case .detail:
                if let detailVM = navigationState.detailViewModel {
                    SessionDetailView(viewModel: detailVM)
                }
            }
        }
    }
}
