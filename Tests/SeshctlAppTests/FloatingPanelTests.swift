import XCTest
import AppKit
import SwiftUI
@testable import SeshctlApp

final class FloatingPanelTests: XCTestCase {
    func test_panelIsTransparent() {
        let panel = FloatingPanel(rootView: EmptyView())
        XCTAssertFalse(panel.isOpaque, "Panel should not be opaque so the visual-effect blur shows through.")
        XCTAssertEqual(panel.backgroundColor, .clear, "Panel backgroundColor should be .clear.")
    }

    func test_contentViewIsVisualEffectWithHUDMaterial() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView, got \(String(describing: panel.contentView)).")
            return
        }
        XCTAssertEqual(effect.material, .hudWindow, "Visual effect material should be .hudWindow.")
        XCTAssertEqual(effect.blendingMode, .behindWindow, "Visual effect blending mode should be .behindWindow.")
        XCTAssertEqual(effect.state, .active, "Visual effect state should be .active.")
    }

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
        XCTAssertEqual(layer.cornerRadius, 20, "Corner radius should be 20.")
        XCTAssertTrue(layer.masksToBounds, "Layer should mask to bounds to clip blur + content to rounded rect.")
        XCTAssertEqual(layer.borderWidth, 1, "Border width should be 1 (hairline stroke).")
        XCTAssertNotNil(layer.borderColor, "Border color should be set.")
    }

    func test_hostingViewIsPinnedSubviewOfEffectView() {
        let panel = FloatingPanel(rootView: EmptyView())
        guard let effect = panel.contentView as? NSVisualEffectView else {
            XCTFail("Expected contentView to be an NSVisualEffectView.")
            return
        }
        XCTAssertEqual(effect.subviews.count, 1, "Effect view should have exactly one subview (the hosting view).")
        guard let hostingView = effect.subviews.first else {
            XCTFail("Expected effect view to have a subview.")
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

    func test_shadowAndFloatingBehaviorPreserved() {
        let panel = FloatingPanel(rootView: EmptyView())
        XCTAssertTrue(panel.hasShadow, "Panel should have a shadow.")
        XCTAssertEqual(panel.level, .floating, "Panel level should be .floating.")
        XCTAssertTrue(panel.isFloatingPanel, "Panel should be marked as a floating panel.")
    }
}
