import XCTest
import AppKit
import SwiftUI
@testable import SeshctlApp
@testable import SeshctlUI

final class FloatingPanelTests: XCTestCase {
    @MainActor
    func test_panelIsTransparent() {
        let panel = FloatingPanel(rootView: EmptyView())
        XCTAssertFalse(panel.isOpaque, "Panel should not be opaque so the visual-effect blur shows through.")
        XCTAssertEqual(panel.backgroundColor, .clear, "Panel backgroundColor should be .clear.")
    }

    @MainActor
    func test_contentViewIsVisualEffectWithPopoverMaterial() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView, got \(String(describing: panel.contentView)).")
            return
        }
        XCTAssertEqual(effect.material, .popover, "Visual effect material should be .popover.")
        XCTAssertEqual(effect.blendingMode, .behindWindow, "Visual effect blending mode should be .behindWindow.")
        XCTAssertEqual(effect.state, .active, "Visual effect state should be .active.")
    }

    @MainActor
    func test_contentViewHasRoundedCornersAndBorder() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView.")
            return
        }
        XCTAssertTrue(effect.wantsLayer, "Effect view should be layer-backed.")
        guard let layer = effect.layer else {
            XCTFail("Expected effect view to have a backing layer.")
            return
        }
        XCTAssertEqual(layer.cornerRadius, FloatingPanel.cornerRadius, "Corner radius should be 20.")
        XCTAssertTrue(layer.masksToBounds, "Layer should mask to bounds to clip blur + content to rounded rect.")
        XCTAssertEqual(layer.borderWidth, FloatingPanel.borderWidth, "Border width should be 1 (hairline stroke).")
        XCTAssertNotNil(layer.borderColor, "Border color should be set.")
    }

    @MainActor
    func test_tintViewIsPinnedSubviewOfEffectView() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView.")
            return
        }
        XCTAssertEqual(effect.subviews.count, 1, "Effect view should have exactly one subview (the tint view).")
        guard let subview = effect.subviews.first else {
            XCTFail("Expected effect view to have a subview.")
            return
        }
        let typeName = String(describing: type(of: subview))
        XCTAssertTrue(
            typeName.contains("LightWhiteTintView"),
            "Expected subview to be a LightWhiteTintView, got type \(typeName)."
        )
        XCTAssertTrue(
            subview.autoresizingMask.contains(.width),
            "Tint view autoresizing mask should contain .width."
        )
        XCTAssertTrue(
            subview.autoresizingMask.contains(.height),
            "Tint view autoresizing mask should contain .height."
        )
    }

    @MainActor
    func test_hostingViewIsPinnedSubviewOfTintView() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView.")
            return
        }
        guard let tintView = effect.subviews.first else {
            XCTFail("Expected effect view to have a tint view subview.")
            return
        }
        XCTAssertEqual(tintView.subviews.count, 1, "Tint view should have exactly one subview (the hosting view).")
        guard let hostingView = tintView.subviews.first else {
            XCTFail("Expected tint view to have a subview.")
            return
        }
        let typeName = String(describing: type(of: hostingView))
        XCTAssertTrue(
            typeName.hasPrefix("NSHostingView<"),
            "Expected subview to be an NSHostingView, got type \(typeName)."
        )
        XCTAssertTrue(
            hostingView.autoresizingMask.contains(.width),
            "Hosting view autoresizing mask should contain .width."
        )
        XCTAssertTrue(
            hostingView.autoresizingMask.contains(.height),
            "Hosting view autoresizing mask should contain .height."
        )
    }

    @MainActor
    func test_shadowAndFloatingBehaviorPreserved() {
        let panel = FloatingPanel(rootView: EmptyView())
        XCTAssertTrue(panel.hasShadow, "Panel should have a shadow.")
        XCTAssertEqual(panel.level, .floating, "Panel level should be .floating.")
        XCTAssertTrue(panel.isFloatingPanel, "Panel should be marked as a floating panel.")
    }

    /// Verifies the Theme.hudBorderNSColor dynamic provider resolves to
    /// different RGBA values under light vs dark appearances. This is the
    /// bedrock guarantee that `PanelBackgroundView.updateLayer` will paint
    /// different border colors when the system switches modes — we test
    /// the dynamic NSColor directly via `performAsCurrentDrawingAppearance`
    /// rather than routing through the NSView's updateLayer cycle, which
    /// is harder to drive synchronously from a unit test.
    func test_hudBorderNSColorResolvesDifferentlyForLightAndDark() {
        let dynamic = Theme.hudBorderNSColor

        var lightRGBA: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var darkRGBA: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)

        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!

        light.performAsCurrentDrawingAppearance {
            let resolved = dynamic.usingColorSpace(.sRGB) ?? dynamic
            lightRGBA = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
        }
        dark.performAsCurrentDrawingAppearance {
            let resolved = dynamic.usingColorSpace(.sRGB) ?? dynamic
            darkRGBA = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
        }

        // Light: black @ 0.12 → (0, 0, 0, 0.12). Dark: white @ 0.15 → (1, 1, 1, 0.15).
        XCTAssertNotEqual(lightRGBA.0, darkRGBA.0, "Red should differ (black vs white).")
        XCTAssertNotEqual(lightRGBA.3, darkRGBA.3, "Alpha should differ (0.12 vs 0.15).")
    }
}
