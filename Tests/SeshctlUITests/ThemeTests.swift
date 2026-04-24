import AppKit
import SwiftUI
import Testing

@testable import SeshctlUI

@MainActor
private func resolveRGBA(
    _ color: Color,
    under appearance: NSAppearance
) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let nsColor = NSColor(color)
    var out: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    appearance.performAsCurrentDrawingAppearance {
        let resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        out = (
            resolved.redComponent,
            resolved.greenComponent,
            resolved.blueComponent,
            resolved.alphaComponent
        )
    }
    return out
}

@MainActor
private func darkAndLightAppearances() -> (dark: NSAppearance, light: NSAppearance)? {
    guard
        let dark = NSAppearance(named: .darkAqua),
        let light = NSAppearance(named: .aqua)
    else { return nil }
    return (dark, light)
}

private let tolerance: CGFloat = 0.001

private func approximatelyEqual(_ a: CGFloat, _ b: CGFloat) -> Bool {
    abs(a - b) < tolerance
}

@Suite("Theme tokens that differ between light and dark")
@MainActor
struct ThemeDifferingTokenTests {
    @Test("textSecondary: system secondaryLabelColor in both modes")
    func textSecondary() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.textSecondary, under: app.dark)
        let light = resolveRGBA(Theme.textSecondary, under: app.light)

        // `NSColor.secondaryLabelColor` has OS-controlled values but is
        // itself adaptive — just assert both resolutions are non-clear
        // grey (alpha > 0, close to grey balance).
        #expect(dark.a > 0)
        #expect(light.a > 0)
    }

    @Test("textTertiary: system tertiaryLabelColor in both modes")
    func textTertiary() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.textTertiary, under: app.dark)
        let light = resolveRGBA(Theme.textTertiary, under: app.light)

        #expect(dark.a > 0)
        #expect(light.a > 0)
    }

    @Test("textPrimaryDimmed: labelColor @ 0.85 (dark) vs black @ 0.80 (light)")
    func textPrimaryDimmed() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.textPrimaryDimmed, under: app.dark)
        let light = resolveRGBA(Theme.textPrimaryDimmed, under: app.light)

        // dark alpha on an OS-controlled color is 0.85 only if the base
        // labelColor has alpha 1.0; that's not guaranteed across OS
        // versions, so just check "not clear".
        #expect(dark.a > 0)

        #expect(approximatelyEqual(light.r, 0))
        #expect(approximatelyEqual(light.g, 0))
        #expect(approximatelyEqual(light.b, 0))
        #expect(approximatelyEqual(light.a, 0.80))
    }

    @Test("hudBorder: white @ 0.15 (dark) vs black @ 0.12 (light)")
    func hudBorder() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.hudBorder, under: app.dark)
        let light = resolveRGBA(Theme.hudBorder, under: app.light)

        // dark: white @ 0.15
        #expect(approximatelyEqual(dark.r, 1))
        #expect(approximatelyEqual(dark.g, 1))
        #expect(approximatelyEqual(dark.b, 1))
        #expect(approximatelyEqual(dark.a, 0.15))

        // light: black @ 0.12
        #expect(approximatelyEqual(light.r, 0))
        #expect(approximatelyEqual(light.g, 0))
        #expect(approximatelyEqual(light.b, 0))
        #expect(approximatelyEqual(light.a, 0.12))
    }

    @Test("panelLightTintOverlay: clear (dark) vs white @ 0.40 (light)")
    func panelLightTintOverlay() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.panelLightTintOverlay, under: app.dark)
        let light = resolveRGBA(Theme.panelLightTintOverlay, under: app.light)

        // dark: fully transparent
        #expect(approximatelyEqual(dark.a, 0))

        // light: white @ 0.40
        #expect(approximatelyEqual(light.r, 1))
        #expect(approximatelyEqual(light.g, 1))
        #expect(approximatelyEqual(light.b, 1))
        #expect(approximatelyEqual(light.a, 0.40))
    }

    @Test("directoryLabel: systemCyan @ 0.70 (dark) vs hand-picked teal (light)")
    func directoryLabel() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.directoryLabel, under: app.dark)
        let light = resolveRGBA(Theme.directoryLabel, under: app.light)

        // dark: systemCyan @ 0.70 — alpha is what we set, RGB is OS-controlled.
        #expect(approximatelyEqual(dark.a, 0.70))

        // light: literal NSColor(red: 0.00, green: 0.45, blue: 0.60, alpha: 1.0)
        #expect(approximatelyEqual(light.r, 0.00))
        #expect(approximatelyEqual(light.g, 0.45))
        #expect(approximatelyEqual(light.b, 0.60))
        #expect(approximatelyEqual(light.a, 1.00))
    }

    @Test("statusStale: gray @ 0.50 (dark) vs black @ 0.35 (light)")
    func statusStale() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.statusStale, under: app.dark)
        let light = resolveRGBA(Theme.statusStale, under: app.light)

        // dark: NSColor.gray — we lock alpha only
        #expect(approximatelyEqual(dark.a, 0.50))

        // light: black @ 0.35
        #expect(approximatelyEqual(light.r, 0))
        #expect(approximatelyEqual(light.g, 0))
        #expect(approximatelyEqual(light.b, 0))
        #expect(approximatelyEqual(light.a, 0.35))
    }

    @Test("searchHighlightCurrent: systemOrange @ 0.60 (dark) vs 0.45 (light)")
    func searchHighlightCurrent() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.searchHighlightCurrent, under: app.dark)
        let light = resolveRGBA(Theme.searchHighlightCurrent, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.60))
        #expect(approximatelyEqual(light.a, 0.45))
    }

    @Test("searchHighlightOther: systemYellow @ 0.25 (dark) vs 0.50 (light)")
    func searchHighlightOther() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.searchHighlightOther, under: app.dark)
        let light = resolveRGBA(Theme.searchHighlightOther, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.25))
        #expect(approximatelyEqual(light.a, 0.50))
    }

    @Test("faintAccentBackground: accent @ 0.06 (dark) vs 0.10 (light)")
    func faintAccentBackground() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.faintAccentBackground, under: app.dark)
        let light = resolveRGBA(Theme.faintAccentBackground, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.06))
        #expect(approximatelyEqual(light.a, 0.10))
    }
}

@Suite("Theme tokens that are identical across appearances")
@MainActor
struct ThemeIdenticalTokenTests {
    @Test("textPrimary resolves to labelColor in both modes (alpha > 0)")
    func textPrimary() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.textPrimary, under: app.dark)
        let light = resolveRGBA(Theme.textPrimary, under: app.light)

        // labelColor is OS-controlled; just confirm both modes resolve
        // to a non-transparent color (provider returned something).
        #expect(dark.a > 0)
        #expect(light.a > 0)
    }

    @Test("selectionTint: controlAccentColor @ 0.20 in both modes")
    func selectionTint() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.selectionTint, under: app.dark)
        let light = resolveRGBA(Theme.selectionTint, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.20))
        #expect(approximatelyEqual(light.a, 0.20))
    }

    @Test("pillBackgroundUnread: systemOrange @ 0.80 in both modes")
    func pillBackgroundUnread() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.pillBackgroundUnread, under: app.dark)
        let light = resolveRGBA(Theme.pillBackgroundUnread, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.80))
        #expect(approximatelyEqual(light.a, 0.80))
    }

    @Test("badgeBackgroundAccent: controlAccentColor @ 0.80 in both modes")
    func badgeBackgroundAccent() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.badgeBackgroundAccent, under: app.dark)
        let light = resolveRGBA(Theme.badgeBackgroundAccent, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.80))
        #expect(approximatelyEqual(light.a, 0.80))
    }

    @Test("pillForeground: white @ 1.00 in both modes")
    func pillForeground() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let dark = resolveRGBA(Theme.pillForeground, under: app.dark)
        let light = resolveRGBA(Theme.pillForeground, under: app.light)

        // white @ 1.00 — literal NSColor, lock full RGBA.
        #expect(approximatelyEqual(dark.r, 1))
        #expect(approximatelyEqual(dark.g, 1))
        #expect(approximatelyEqual(dark.b, 1))
        #expect(approximatelyEqual(dark.a, 1))

        #expect(approximatelyEqual(light.r, 1))
        #expect(approximatelyEqual(light.g, 1))
        #expect(approximatelyEqual(light.b, 1))
        #expect(approximatelyEqual(light.a, 1))
    }
}

@Suite("Theme.bannerBackground")
@MainActor
struct ThemeBannerBackgroundTests {
    @Test("bannerBackground(tint: .red) alpha is 0.12 in dark and 0.18 in light")
    func bannerBackgroundAlphaBumpsOnLight() {
        guard let app = darkAndLightAppearances() else {
            Issue.record("Unable to construct dark/light appearances")
            return
        }
        let banner = Theme.bannerBackground(tint: .red)
        let dark = resolveRGBA(banner, under: app.dark)
        let light = resolveRGBA(banner, under: app.light)

        #expect(approximatelyEqual(dark.a, 0.12))
        #expect(approximatelyEqual(light.a, 0.18))
    }
}

@Suite("Theme.statusHaloAlpha")
struct ThemeStatusHaloAlphaTests {
    @Test(".outer dark 0.40 / light 0.50")
    func outerLevel() {
        #expect(Theme.statusHaloAlpha(.outer, colorScheme: .dark) == 0.40)
        #expect(Theme.statusHaloAlpha(.outer, colorScheme: .light) == 0.50)
    }

    @Test(".inner dark 0.25 / light 0.35")
    func innerLevel() {
        #expect(Theme.statusHaloAlpha(.inner, colorScheme: .dark) == 0.25)
        #expect(Theme.statusHaloAlpha(.inner, colorScheme: .light) == 0.35)
    }

    @Test(".shadow dark 0.80 / light 0.85")
    func shadowLevel() {
        #expect(Theme.statusHaloAlpha(.shadow, colorScheme: .dark) == 0.80)
        #expect(Theme.statusHaloAlpha(.shadow, colorScheme: .light) == 0.85)
    }
}
