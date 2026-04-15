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
            let vm = SessionListViewModel(database: db, defaults: .standard)
            viewModel = vm

            let nav = navigationState

            // Create panel with root view that switches between list and detail
            let rootView = RootView(
                navigationState: nav,
                listViewModel: vm,
                onSessionTap: { [weak self] session in
                    guard let self, let vm = self.viewModel else { return }
                    let target: SessionActionTarget = session.isActive
                        ? .activeSession(session) : .inactiveSession(session)
                    SessionAction.execute(
                        target: target,
                        markRead: { vm.markSessionRead($0) },
                        rememberFocused: { vm.rememberFocusedSession($0) },
                        dismiss: { self.dismissPanel() }
                    )
                },
                onOpenDetail: { [weak nav] session in
                    nav?.openDetail(for: session)
                },
                onOpenRecallDetail: { [weak nav] result, session in
                    nav?.openDetail(for: result, session: session)
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
                self?.viewModel?.recordPanelClose()
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
        viewModel?.applyInboxAwareResetIfNeeded()
        viewModel?.panelDidShow()
        viewModel?.resetSelection()
    }

    private func dismissPanel() {
        panel?.orderOut(nil)
        viewModel?.recordPanelClose()
        viewModel?.panelDidHide()
    }

    private func togglePanel() {
        panel?.toggle()
        viewModel?.exitSearch()
        if panel?.isVisible == true {
            viewModel?.applyInboxAwareResetIfNeeded()
            viewModel?.panelDidShow()
            viewModel?.resetSelection()
            // Return to list when reopening
            if navigationState.screen == .detail {
                navigationState.backToList()
            }
        } else {
            viewModel?.recordPanelClose()
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
            handleNormalKey(keyCode: keyCode, chars: chars, modifiers: modifiers, vm: vm)
        }
    }

    private func handleNormalKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags, vm: SessionListViewModel) {
        // Handle gg sequence: if g is pending and another g arrives, go to top
        if pendingG {
            pendingG = false
            if chars == "g" {
                vm.moveToTop()
                return
            }
            // Not a second g — fall through to normal handling
        }

        // Shift+Tab — move up
        if keyCode == 48 && modifiers.contains(.shift) {
            vm.moveSelectionUp()
            return
        }

        // Ctrl+key combos
        if modifiers.contains(.control), let chars {
            switch chars {
            case "d": vm.moveSelectionBy(8); return
            case "u": vm.moveSelectionBy(-8); return
            case "f": vm.moveSelectionBy(15); return
            case "b": vm.moveSelectionBy(-15); return
            default: break
            }
        }

        switch (keyCode, chars) {
        // / to enter search
        case (_, "/"):
            if vm.pendingKillSessionId == nil && !vm.pendingMarkAllRead {
                vm.enterSearch()
            }
        // v — toggle list/tree view mode
        case (_, "v"):
            if vm.pendingKillSessionId == nil && !vm.pendingMarkAllRead {
                vm.toggleViewMode()
            }
        // G (shift+g) — go to bottom
        case (_, "G"):
            vm.moveToBottom()
        // g — start gg sequence
        case (_, "g"):
            pendingG = true
        // j, Down arrow, or Tab
        case (_, "j"), (125, _), (48, _):
            vm.moveSelectionDown()
        // k or Up arrow
        case (_, "k"), (126, _):
            vm.moveSelectionUp()
        // l or Right arrow — jump to next group (tree mode only)
        case (_, "l"), (124, _):
            if vm.isTreeMode { vm.jumpToNextGroup() }
        // h or Left arrow — jump to previous group (tree mode only)
        case (_, "h"), (123, _):
            if vm.isTreeMode { vm.jumpToPreviousGroup() }
        // Home key — go to top
        case (115, _):
            vm.moveToTop()
        // End key — go to bottom
        case (119, _):
            vm.moveToBottom()
        // U (shift+u) — mark all as read
        case (_, "U"):
            if vm.pendingKillSessionId == nil && !vm.pendingMarkAllRead {
                vm.requestMarkAllRead()
            }
        // u — mark as read
        case (_, "u"):
            if let session = vm.selectedSession {
                vm.markSessionRead(session)
            }
        // o — open detail view
        case (_, "o"):
            openDetailForSelected(vm: vm)
        // Enter, Return, or e
        case (36, _), (76, _), (_, "e"):
            executeSessionAction(vm: vm)
        // x — kill session process
        case (_, "x"):
            if vm.pendingKillSessionId == nil {
                vm.requestKill()
            }
        // y — confirm kill or mark all read
        case (_, "y"):
            if vm.pendingKillSessionId != nil {
                vm.confirmKill()
            } else if vm.pendingMarkAllRead {
                vm.confirmMarkAllRead()
            }
        // n — cancel kill or mark all read
        case (_, "n"):
            if vm.pendingKillSessionId != nil {
                vm.cancelKill()
            } else if vm.pendingMarkAllRead {
                vm.cancelMarkAllRead()
            }
        // q or Escape — cancel kill/mark all read or close panel
        case (_, "q"), (53, _):
            if vm.pendingKillSessionId != nil {
                vm.cancelKill()
            } else if vm.pendingMarkAllRead {
                vm.cancelMarkAllRead()
            } else {
                dismissPanel()
            }
        default:
            break
        }
    }

    private func handleDetailKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags, vm: SessionDetailViewModel) {
        // Handle search mode input
        if vm.isSearching {
            handleDetailSearchKey(keyCode: keyCode, chars: chars, modifiers: modifiers, vm: vm)
            return
        }

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
        // / — enter search mode
        case (_, "/"):
            vm.enterSearch()
        // n — next search match
        case (_, "n"):
            vm.nextMatch()
        // N — previous search match
        case (_, "N"):
            vm.previousMatch()
        default:
            break
        }
    }

    private func handleDetailSearchKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags, vm: SessionDetailViewModel) {
        switch keyCode {
        // Escape — exit search
        case 53:
            vm.exitSearch()
        // Enter/Return — confirm search (exit typing mode but keep matches highlighted)
        case 36, 76:
            vm.isSearching = false
        // Delete/Backspace
        case 51:
            vm.deleteSearchCharacter()
        // Cmd+V — paste from clipboard
        case 9 where modifiers.contains(.command):
            if let paste = NSPasteboard.general.string(forType: .string) {
                let sanitized = paste.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "")
                vm.appendSearchCharacter(sanitized)
            }
        // Ctrl+W — delete word backward
        case 13 where modifiers.contains(.control):
            vm.deleteSearchWord()
        // Ctrl+U — clear search query
        case 32 where modifiers.contains(.control):
            vm.clearSearchQuery()
        default:
            if let chars, !chars.isEmpty, !modifiers.contains(.control), !modifiers.contains(.command) {
                vm.appendSearchCharacter(chars)
            }
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
        // Enter/Return — focus selected session or handle recall result
        case 36, 76:
            executeSessionAction(vm: vm)
        // Down arrow
        case 125:
            vm.moveSelectionDown()
        // Up arrow
        case 126:
            vm.moveSelectionUp()
        // Cmd+V — paste from clipboard
        case 9 where modifiers.contains(.command):
            if let paste = NSPasteboard.general.string(forType: .string) {
                if vm.isNavigatingSearch { vm.isNavigatingSearch = false }
                let sanitized = paste.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "")
                vm.appendSearchCharacter(sanitized)
            }
        // Ctrl+W — delete word backward
        case 13 where modifiers.contains(.control):
            if vm.isNavigatingSearch { vm.isNavigatingSearch = false }
            vm.deleteSearchWord()
        // Ctrl+U — clear search query
        case 32 where modifiers.contains(.control):
            if vm.isNavigatingSearch { vm.isNavigatingSearch = false }
            vm.clearSearchQuery()
        default:
            if vm.isNavigatingSearch {
                // j/k navigation while in nav mode
                if chars == "j" {
                    vm.moveSelectionDown()
                } else if chars == "k" {
                    vm.moveSelectionUp()
                } else if chars == "o" {
                    openDetailForSelected(vm: vm)
                }
            } else if let chars, !chars.isEmpty {
                vm.appendSearchCharacter(chars)
            }
        }
    }

    private func openDetailForSelected(vm: SessionListViewModel) {
        if let session = vm.selectedSession {
            pendingG = false
            vm.markSessionRead(session)
            navigationState.openDetail(for: session)
        } else if let result = vm.selectedRecallResult {
            pendingG = false
            navigationState.openDetail(for: result, session: vm.session(for: result))
        }
    }

    private func executeSessionAction(vm: SessionListViewModel) {
        let target: SessionActionTarget
        if let session = vm.selectedSession {
            target = session.isActive ? .activeSession(session) : .inactiveSession(session)
        } else if let result = vm.selectedRecallResult {
            target = .recallResult(result, matchedSession: vm.session(for: result))
        } else {
            return
        }

        SessionAction.execute(
            target: target,
            markRead: { vm.markSessionRead($0) },
            rememberFocused: { vm.rememberFocusedSession($0) },
            dismiss: { [weak self] in self?.dismissPanel() }
        )
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
    var onOpenRecallDetail: ((RecallResult, Session?) -> Void)?

    var body: some View {
        Group {
            switch navigationState.screen {
            case .list:
                SessionListView(viewModel: listViewModel, onSessionTap: onSessionTap, onOpenDetail: onOpenDetail, onOpenRecallDetail: onOpenRecallDetail)
            case .detail:
                if let detailVM = navigationState.detailViewModel {
                    SessionDetailView(viewModel: detailVM)
                }
            }
        }
    }
}
