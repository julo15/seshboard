import AppKit
import SwiftUI

/// A floating NSPanel that behaves like Spotlight:
/// - Doesn't appear in Cmd+Tab or Mission Control
/// - Stays above other windows
/// - Click outside to dismiss
/// - Vim-style keyboard navigation (j/k, arrows, enter, esc)
final class FloatingPanel: NSPanel {
    var onKeyDown: ((UInt16, String?, NSEvent.ModifierFlags) -> Void)?
    var onDismiss: (() -> Void)?

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Floating behavior
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Hide traffic light buttons so titlebar is purely invisible
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // Visual style — Spotlight-like translucent glass
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Content: NSVisualEffectView behind, NSHostingView pinned on top.
        // Layer-backed effect view gives us rounded corners + hairline stroke;
        // masksToBounds clips the blur and the SwiftUI content to the rounded rect,
        // and the window shadow follows the resulting alpha mask.
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 900, height: 720))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        contentView = effect

        // ignoresSafeArea so the view extends under the transparent titlebar
        let hostingView = NSHostingView(rootView: rootView.ignoresSafeArea())
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        effect.addSubview(hostingView)
    }

    /// Center the panel on the main screen.
    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            centerOnScreen()
            makeKeyAndOrderFront(nil)
        }
    }

    // Dismiss on click outside (but not when already hidden programmatically)
    override func resignKey() {
        super.resignKey()
        guard isVisible else { return }
        orderOut(nil)
        onDismiss?()
    }

    // Allow the panel to become key (for receiving keyboard events)
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers
        onKeyDown?(event.keyCode, chars, event.modifierFlags)
    }
}
