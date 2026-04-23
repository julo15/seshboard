import AppKit
import Foundation

/// Single source of truth for appearance-related UserDefaults keys.
/// Views wire `@AppStorage(AppearanceDefaults.repoAccentBarKey)` instead of
/// hard-coding the key string — avoids typo drift across the ~5 views that
/// observe the same setting.
public enum AppearanceDefaults {
    /// Key for the "Repo color coding" toggle. Follows the `seshctl.`
    /// prefix convention used by `SessionListViewModel` for other
    /// UserDefaults keys.
    public static let repoAccentBarKey = "seshctl.repoAccentBarEnabled"

    /// Default for the toggle — on, so existing users and fresh installs
    /// see the feature by default.
    public static let repoAccentBarDefault = true

    /// Key for the "Appearance" picker (System / Light / Dark).
    public static let appearancePreferenceKey = "seshctl.appearancePreference"

    /// Default — follow the system appearance.
    public static let appearancePreferenceDefault: AppearancePreference = .system

    /// Apply the stored `AppearancePreference` to `NSApp.appearance`. Call
    /// once at app launch (after `NSApp` is available) so the user's choice
    /// takes effect before the first window renders.
    @MainActor
    public static func applyStoredAppearancePreference(defaults: UserDefaults = .standard) {
        let raw = defaults.string(forKey: appearancePreferenceKey) ?? appearancePreferenceDefault.rawValue
        let pref = AppearancePreference(rawValue: raw) ?? appearancePreferenceDefault
        NSApp.appearance = pref.nsAppearance
    }

    /// One-shot migration from the pre-release un-prefixed key
    /// (`"repoAccentBarEnabled"`) to `seshctl.repoAccentBarEnabled`.
    /// Run once at app launch so an author who toggled the setting during
    /// dev doesn't silently lose their choice when the key rename ships.
    /// Safe to call repeatedly — no-op after the first successful copy.
    public static func migrateLegacyKey(defaults: UserDefaults = .standard) {
        let legacy = "repoAccentBarEnabled"
        guard defaults.object(forKey: legacy) != nil,
              defaults.object(forKey: repoAccentBarKey) == nil else {
            return
        }
        defaults.set(defaults.bool(forKey: legacy), forKey: repoAccentBarKey)
        defaults.removeObject(forKey: legacy)
    }
}
