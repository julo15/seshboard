import AppKit
import KeyboardShortcuts
import SeshboardCore
import SeshboardUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.s, modifiers: [.command, .shift]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var viewModel: SessionListViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Set up database and view model
        do {
            let path = NSString(
                string: "~/.local/share/seshboard/seshboard.db"
            ).expandingTildeInPath
            let db = try SeshboardDatabase(path: path)
            let vm = SessionListViewModel(database: db)
            viewModel = vm

            // Create panel
            let panelRef = FloatingPanel(rootView:
                SessionListView(viewModel: vm) { [weak self] session in
                    self?.focusSession(session)
                }
            )
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
            alert.messageText = "Seshboard failed to start"
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

    private func togglePanel() {
        panel?.toggle()
        viewModel?.resetSelection()
        viewModel?.exitSearch()
        if panel?.isVisible == true {
            viewModel?.panelDidShow()
        } else {
            viewModel?.panelDidHide()
        }
    }

    private func handleKey(keyCode: UInt16, chars: String?, modifiers: NSEvent.ModifierFlags) {
        guard let vm = viewModel else { return }

        if vm.isSearching {
            handleSearchKey(keyCode: keyCode, chars: chars, modifiers: modifiers, vm: vm)
        } else {
            handleNormalKey(keyCode: keyCode, chars: chars, vm: vm)
        }
    }

    private func handleNormalKey(keyCode: UInt16, chars: String?, vm: SessionListViewModel) {
        switch (keyCode, chars) {
        // / to enter search
        case (_, "/"):
            vm.enterSearch()
        // j or Down arrow
        case (_, "j"), (125, _):
            vm.moveSelectionDown()
        // k or Up arrow
        case (_, "k"), (126, _):
            vm.moveSelectionUp()
        // Enter or Return
        case (36, _), (76, _):
            if let session = vm.selectedSession {
                focusSession(session)
            }
        // Escape
        case (53, _):
            panel?.orderOut(nil)
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
        if let pid = session.pid {
            WindowFocuser.focus(pid: pid, directory: session.directory)
        }
        panel?.orderOut(nil)
        viewModel?.panelDidHide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
