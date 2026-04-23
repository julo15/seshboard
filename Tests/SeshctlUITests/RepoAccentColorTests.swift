import AppKit
import Foundation
import SwiftUI
import Testing

@testable import SeshctlUI

@Suite("RepoAccentColor")
struct RepoAccentColorTests {
    @Test("Returns nil for nil input")
    func nilInput() {
        #expect(repoAccentColor(for: nil) == nil)
    }

    @Test("Returns nil for empty string")
    func emptyInput() {
        #expect(repoAccentColor(for: "") == nil)
    }

    @Test("Same repo name always returns the same color")
    func deterministic() {
        #expect(repoAccentColor(for: "seshctl") == repoAccentColor(for: "seshctl"))
        #expect(repoAccentColor(for: "mozi-app") == repoAccentColor(for: "mozi-app"))
    }

    @Test("Palette contains exactly 10 colors")
    func paletteSize() {
        #expect(repoAccentPalette.count == 10)
    }

    @Test("Common repo names distribute across the palette (no single-bucket collapse)")
    func distribution() {
        let names = ["seshctl", "mozi-app", "dashboard", "infra", "api", "web", "cli", "docs"]
        let colors = Set(names.compactMap { repoAccentColor(for: $0) })
        // With 10 palette slots and 8 inputs, at least 4 distinct colors is a
        // reasonable floor — guards against a buggy hash that collapses into
        // one bucket. Exact count is allowed to drift if we tune the palette.
        #expect(colors.count >= 4)
    }

    @Test("Every palette slot resolves to different RGB in dark vs light mode")
    @MainActor
    func adaptivePalette() {
        guard
            let darkAppearance = NSAppearance(named: .darkAqua),
            let lightAppearance = NSAppearance(named: .aqua)
        else {
            Issue.record("Unable to construct dark/light NSAppearance")
            return
        }

        for (index, color) in repoAccentPalette.enumerated() {
            let nsColor = NSColor(color)

            var darkRGB: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            darkAppearance.performAsCurrentDrawingAppearance {
                let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
                darkRGB = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
            }

            var lightRGB: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
            lightAppearance.performAsCurrentDrawingAppearance {
                let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
                lightRGB = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
            }

            let differs =
                darkRGB.0 != lightRGB.0
                || darkRGB.1 != lightRGB.1
                || darkRGB.2 != lightRGB.2
            #expect(differs, "Palette slot \(index) must differ between dark and light mode")
        }
    }
}
