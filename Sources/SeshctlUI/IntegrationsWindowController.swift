import AppKit
import SwiftUI
import SeshctlCore

/// NSWindowController that hosts `IntegrationsView` in a non-resizable window
/// titled "Editor Integrations". Used by AppDelegate / SettingsPopover via
/// `IntegrationsWindowController.shared.showWindow(nil)`.
@MainActor
public final class IntegrationsWindowController: NSWindowController {
    /// Lazily-created singleton wired to the production `NSWorkspaceAppLocator`
    /// and `Bundle.main.bundleURL`. AppDelegate and SettingsPopover both call
    /// `IntegrationsWindowController.shared.showWindow(nil)`.
    public static let shared: IntegrationsWindowController = {
        let installer = ExtensionInstaller(appLocator: NSWorkspaceAppLocator())
        return IntegrationsWindowController(installer: installer, bundleURL: Bundle.main.bundleURL)
    }()

    public init(installer: ExtensionInstaller, bundleURL: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Editor Integrations"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: IntegrationsView(
                installer: installer,
                bundleURL: bundleURL,
                onClose: { [weak self] in self?.close() }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not implemented") }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
