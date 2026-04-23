import AppKit
import Testing

@testable import SeshctlUI

@Suite("AppearancePreference")
struct AppearancePreferenceTests {
    @Test(".system displayName is System")
    func systemDisplayName() {
        #expect(AppearancePreference.system.displayName == "System")
    }

    @Test(".light displayName is Light")
    func lightDisplayName() {
        #expect(AppearancePreference.light.displayName == "Light")
    }

    @Test(".dark displayName is Dark")
    func darkDisplayName() {
        #expect(AppearancePreference.dark.displayName == "Dark")
    }

    @Test(".system.nsAppearance is nil")
    func systemNSAppearanceIsNil() {
        #expect(AppearancePreference.system.nsAppearance == nil)
    }

    @Test(".light.nsAppearance is .aqua")
    func lightNSAppearanceIsAqua() {
        #expect(AppearancePreference.light.nsAppearance?.name == .aqua)
    }

    @Test(".dark.nsAppearance is .darkAqua")
    func darkNSAppearanceIsDarkAqua() {
        #expect(AppearancePreference.dark.nsAppearance?.name == .darkAqua)
    }

    @Test("rawValue round-trip: system")
    func rawValueRoundTripSystem() {
        #expect(AppearancePreference(rawValue: "system") == .system)
    }

    @Test("rawValue round-trip: light")
    func rawValueRoundTripLight() {
        #expect(AppearancePreference(rawValue: "light") == .light)
    }

    @Test("rawValue round-trip: dark")
    func rawValueRoundTripDark() {
        #expect(AppearancePreference(rawValue: "dark") == .dark)
    }

    @Test("rawValue bogus returns nil")
    func rawValueBogusReturnsNil() {
        #expect(AppearancePreference(rawValue: "bogus") == nil)
    }
}
