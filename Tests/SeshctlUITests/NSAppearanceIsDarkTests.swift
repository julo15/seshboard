import AppKit
import Testing

@testable import SeshctlUI

@Suite("NSAppearance.isDarkMode")
struct NSAppearanceIsDarkTests {
    @Test(".darkAqua is dark")
    func darkAquaIsDark() {
        guard let appearance = NSAppearance(named: .darkAqua) else {
            Issue.record("Unable to construct .darkAqua appearance")
            return
        }
        #expect(appearance.isDarkMode == true)
    }

    @Test(".vibrantDark is dark")
    func vibrantDarkIsDark() {
        guard let appearance = NSAppearance(named: .vibrantDark) else {
            Issue.record("Unable to construct .vibrantDark appearance")
            return
        }
        #expect(appearance.isDarkMode == true)
    }

    @Test(".accessibilityHighContrastDarkAqua is dark")
    func accessibilityHighContrastDarkAquaIsDark() {
        guard let appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua) else {
            Issue.record("Unable to construct .accessibilityHighContrastDarkAqua appearance")
            return
        }
        #expect(appearance.isDarkMode == true)
    }

    @Test(".accessibilityHighContrastVibrantDark is dark")
    func accessibilityHighContrastVibrantDarkIsDark() {
        guard let appearance = NSAppearance(named: .accessibilityHighContrastVibrantDark) else {
            Issue.record("Unable to construct .accessibilityHighContrastVibrantDark appearance")
            return
        }
        #expect(appearance.isDarkMode == true)
    }

    @Test(".aqua is light")
    func aquaIsLight() {
        guard let appearance = NSAppearance(named: .aqua) else {
            Issue.record("Unable to construct .aqua appearance")
            return
        }
        #expect(appearance.isDarkMode == false)
    }

    @Test(".vibrantLight is light")
    func vibrantLightIsLight() {
        guard let appearance = NSAppearance(named: .vibrantLight) else {
            Issue.record("Unable to construct .vibrantLight appearance")
            return
        }
        #expect(appearance.isDarkMode == false)
    }

    @Test(".accessibilityHighContrastAqua is light")
    func accessibilityHighContrastAquaIsLight() {
        guard let appearance = NSAppearance(named: .accessibilityHighContrastAqua) else {
            Issue.record("Unable to construct .accessibilityHighContrastAqua appearance")
            return
        }
        #expect(appearance.isDarkMode == false)
    }

    @Test(".accessibilityHighContrastVibrantLight is light")
    func accessibilityHighContrastVibrantLightIsLight() {
        guard let appearance = NSAppearance(named: .accessibilityHighContrastVibrantLight) else {
            Issue.record("Unable to construct .accessibilityHighContrastVibrantLight appearance")
            return
        }
        #expect(appearance.isDarkMode == false)
    }
}
