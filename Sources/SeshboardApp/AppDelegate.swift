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
            panelRef.onKeyDown = { [weak self] keyCode, chars in
                self?.handleKey(keyCode: keyCode, chars: chars)
            }

            // Start polling
            vm.startPolling()
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
    }

    private func togglePanel() {
        panel?.toggle()
        viewModel?.resetSelection()
    }

    private func handleKey(keyCode: UInt16, chars: String?) {
        guard let vm = viewModel else { return }

        switch (keyCode, chars) {
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

    private func focusSession(_ session: Session) {
        if let pid = session.pid {
            WindowFocuser.focus(pid: pid, directory: session.directory)
        }
        panel?.orderOut(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
