import AppKit
import SwiftUI
import SeshctlUI

/// A floating NSPanel that behaves like Spotlight:
/// - Doesn't appear in Cmd+Tab or Mission Control
/// - Stays above other windows
/// - Click outside to dismiss
/// - Vim-style keyboard navigation (j/k, arrows, enter, esc)
final class FloatingPanel: NSPanel {
    // Chrome constants — Spotlight-like translucent HUD glass.
    static let panelSize = NSSize(width: 900, height: 720)
    static let cornerRadius: CGFloat = 20
    static let borderWidth: CGFloat = 1

    var onKeyDown: ((UInt16, String?, NSEvent.ModifierFlags) -> Void)?
    var onDismiss: (() -> Void)?

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingPanel.panelSize),
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

        // Content: PanelBackgroundView (NSVisualEffectView) behind, a
        // LightWhiteTintView pinned on top, and the NSHostingView pinned
        // inside that. Layer-backed effect view gives us rounded corners +
        // hairline stroke; masksToBounds clips the blur and the SwiftUI
        // content to the rounded rect, and the window shadow follows the
        // resulting alpha mask.
        //
        // The border color and tint overlay are pulled from Theme NSColor
        // tokens. Both subviews override `updateLayer` so the CGColors
        // re-resolve against the view's `effectiveAppearance` on every
        // appearance flip — no staleness across light/dark switches.
        let effect = PanelBackgroundView(frame: NSRect(origin: .zero, size: FloatingPanel.panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = FloatingPanel.cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = FloatingPanel.borderWidth
        effect.layer?.borderColor = Theme.hudBorderNSColor.cgColor
        contentView = effect

        let tintView = LightWhiteTintView(frame: effect.bounds)
        tintView.autoresizingMask = [.width, .height]
        effect.addSubview(tintView)

        // ignoresSafeArea so the view extends under the transparent titlebar
        let hostingView = NSHostingView(rootView: rootView.ignoresSafeArea())
        hostingView.frame = tintView.bounds
        hostingView.autoresizingMask = [.width, .height]
        tintView.addSubview(hostingView)
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

/// Layer-backed `NSVisualEffectView` that re-resolves the Theme hairline
/// border CGColor on every appearance change. `updateLayer` runs with
/// `NSAppearance.current` set to the view's `effectiveAppearance`, so
/// the dynamic Theme provider flips correctly between light and dark.
private final class PanelBackgroundView: NSVisualEffectView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        // Inside updateLayer, NSAppearance.current is set to the view's
        // effectiveAppearance, so cgColor resolves against the right mode.
        layer?.borderColor = Theme.hudBorderNSColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A transparent-in-dark / white-wash-in-light overlay painted between
/// the frosted `.popover` material and the SwiftUI content. Same dynamic
/// pattern as `PanelBackgroundView`: `updateLayer` re-resolves the Theme
/// NSColor against the current appearance.
private final class LightWhiteTintView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = Theme.panelLightTintOverlayNSColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
