import AppKit
import SwiftUI

/// A floating NSPanel that behaves like Spotlight:
/// - Doesn't appear in Cmd+Tab or Mission Control
/// - Stays above other windows
/// - Click outside to dismiss
/// - Vim-style keyboard navigation (j/k, arrows, enter, esc)
final class FloatingPanel: NSPanel {
    var onKeyDown: ((UInt16, String?) -> Void)?
    var onDismiss: (() -> Void)?

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
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
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // Visual style
        backgroundColor = .windowBackgroundColor
        isOpaque = true
        hasShadow = true

        // Content
        contentView = NSHostingView(rootView: rootView)
    }

    /// Center the panel on the main screen.
    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2 + screenFrame.height * 0.1
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

    // Dismiss on click outside
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
        onDismiss?()
    }

    // Allow the panel to become key (for receiving keyboard events)
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers
        onKeyDown?(event.keyCode, chars)
    }
}
