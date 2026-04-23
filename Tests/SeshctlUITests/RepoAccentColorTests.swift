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
}
