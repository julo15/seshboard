import AppKit
import Foundation
import Testing

@testable import SeshctlUI

@Suite("AppearanceDefaults.applyStoredAppearancePreference")
@MainActor
struct AppearanceDefaultsTests {
    @Test("stored 'dark' sets NSApp.appearance to .darkAqua")
    func storedDarkAppliesDarkAqua() {
        _ = NSApplication.shared
        let suite = "AppearanceDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to build scratch UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("dark", forKey: AppearanceDefaults.appearancePreferenceKey)
        AppearanceDefaults.applyStoredAppearancePreference(defaults: defaults)
        #expect(NSApp.appearance?.name == .darkAqua)
    }

    @Test("stored 'light' sets NSApp.appearance to .aqua")
    func storedLightAppliesAqua() {
        _ = NSApplication.shared
        let suite = "AppearanceDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to build scratch UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("light", forKey: AppearanceDefaults.appearancePreferenceKey)
        AppearanceDefaults.applyStoredAppearancePreference(defaults: defaults)
        #expect(NSApp.appearance?.name == .aqua)
    }

    @Test("missing key resets NSApp.appearance to nil (follow system)")
    func missingKeyFollowsSystem() {
        _ = NSApplication.shared
        let suite = "AppearanceDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to build scratch UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.removeObject(forKey: AppearanceDefaults.appearancePreferenceKey)
        AppearanceDefaults.applyStoredAppearancePreference(defaults: defaults)
        #expect(NSApp.appearance == nil)
    }

    @Test("stored pref overrides ambient NSApp.appearance")
    func storedPrefOverridesAmbient() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let suite = "AppearanceDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("Failed to build scratch UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("light", forKey: AppearanceDefaults.appearancePreferenceKey)
        AppearanceDefaults.applyStoredAppearancePreference(defaults: defaults)
        #expect(NSApp.appearance?.name == .aqua)
    }
}
