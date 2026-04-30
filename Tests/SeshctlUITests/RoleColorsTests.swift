import AppKit
import SwiftUI
import Testing

@testable import SeshctlUI

@Suite("Color.assistantPurple (adaptive)")
@MainActor
struct RoleColorsTests {
    @Test("Dark: #937CBF (0x93, 0x7C, 0xBF)")
    func darkHex() {
        guard let dark = NSAppearance(named: .darkAqua) else {
            Issue.record("Unable to construct .darkAqua appearance")
            return
        }
        let nsColor = NSColor(Color.assistantPurple)
        var rgb: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        dark.performAsCurrentDrawingAppearance {
            let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
            rgb = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }
        // Allow a small tolerance for sRGB conversion noise.
        #expect(abs(rgb.0 - 0x93 / 255.0) < 0.01)
        #expect(abs(rgb.1 - 0x7C / 255.0) < 0.01)
        #expect(abs(rgb.2 - 0xBF / 255.0) < 0.01)
    }

    @Test("Light: #6B53A0 (0x6B, 0x53, 0xA0) — denser purple for white backgrounds")
    func lightHex() {
        guard let light = NSAppearance(named: .aqua) else {
            Issue.record("Unable to construct .aqua appearance")
            return
        }
        let nsColor = NSColor(Color.assistantPurple)
        var rgb: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        light.performAsCurrentDrawingAppearance {
            let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
            rgb = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }
        #expect(abs(rgb.0 - 0x6B / 255.0) < 0.01)
        #expect(abs(rgb.1 - 0x53 / 255.0) < 0.01)
        #expect(abs(rgb.2 - 0xA0 / 255.0) < 0.01)
    }
}
