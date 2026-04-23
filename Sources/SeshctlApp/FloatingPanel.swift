import AppKit
import SwiftUI

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
    static let borderAlpha: CGFloat = 0.15

    // Entrance animation constants — Spotlight-style pop.
    static let entranceInitialScale: CGFloat = 0.94
    static let entranceFadeDuration: CFTimeInterval = 0.05
    static let entranceSpringDamping: CGFloat = 38
    static let entranceSpringStiffness: CGFloat = 1200
    static let entranceSpringMass: CGFloat = 0.5

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
        // We own the entrance animation (spring + fade in animateIn()), so disable the
        // default AppKit fade — otherwise both run and the pop gets muddied. Side
        // effect: the hide path (orderOut from toggle/resignKey/dismissPanel) is now
        // instant, which matches Spotlight. If you want a fade-out later, animate
        // alphaValue to 0 manually before orderOut rather than flipping this back.
        animationBehavior = .none

        // Visual style — Spotlight-like translucent glass
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Content: NSVisualEffectView behind, NSHostingView pinned on top.
        // Layer-backed effect view gives us rounded corners + hairline stroke;
        // masksToBounds clips the blur and the SwiftUI content to the rounded rect,
        // and the window shadow follows the resulting alpha mask.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: FloatingPanel.panelSize))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        effect.layer?.cornerRadius = FloatingPanel.cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = FloatingPanel.borderWidth
        // Note: CGColor is captured at init; won't re-resolve on light/dark switch while the panel is open (panel is transient, so drift is narrow).
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(FloatingPanel.borderAlpha).cgColor
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
            animateIn()
        }
    }

    /// Spotlight-style entrance: fade in the window alpha while springing the content
    /// layer from a slight shrink up to full size. The window shadow follows the
    /// effect view's alpha mask, so it pops in together with the glass. Honours
    /// Reduce Motion by showing the panel instantly with no animation.
    private func animateIn() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 1
            makeKeyAndOrderFront(nil)
            return
        }

        guard let layer = (contentView as? NSVisualEffectView)?.layer else {
            alphaValue = 1
            makeKeyAndOrderFront(nil)
            return
        }

        // Layer-backed NSViews default to anchorPoint (0, 0), which would scale from
        // the bottom-left. Re-anchor to the center and compensate position so the
        // layer doesn't jump, then we can use a plain scale transform.
        let bounds = layer.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        // Seed the starting state before the window is visible to avoid a flash.
        alphaValue = 0
        let initialScale = FloatingPanel.entranceInitialScale
        layer.transform = CATransform3DMakeScale(initialScale, initialScale, 1)
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingPanel.entranceFadeDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            animator().alphaValue = 1
        }

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeScale(initialScale, initialScale, 1)
        spring.toValue = CATransform3DIdentity
        spring.damping = FloatingPanel.entranceSpringDamping
        spring.stiffness = FloatingPanel.entranceSpringStiffness
        spring.mass = FloatingPanel.entranceSpringMass
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "entrance-pop")
        layer.transform = CATransform3DIdentity
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
