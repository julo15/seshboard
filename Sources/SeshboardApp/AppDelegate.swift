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
                    // Focus the session's terminal window and dismiss the panel
                    if let pid = session.pid {
                        WindowFocuser.focus(pid: pid, directory: session.directory)
                    }
                    self?.panel?.orderOut(nil)
                }
            )
            panel = panelRef

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
            self?.panel?.toggle()
        }

        // Show panel on launch
        panel?.toggle()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
