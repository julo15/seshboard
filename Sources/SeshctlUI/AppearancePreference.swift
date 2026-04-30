import AppKit
import Foundation

/// User-selectable app appearance. `.system` follows System Settings →
/// Appearance; `.light` and `.dark` force the matching `NSAppearance`
/// regardless of system setting.
///
/// Raw values are stable strings so `@AppStorage` persistence survives
/// refactors. Wired through `AppearanceDefaults.appearancePreferenceKey`.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `NSAppearance` to apply to `NSApp.appearance`. `nil` means "follow
    /// system" — AppKit inherits the system appearance when the app's
    /// appearance property is nil.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
