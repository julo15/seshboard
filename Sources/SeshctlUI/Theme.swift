import AppKit
import SwiftUI

/// Semantic color tokens for Seshctl's UI. Each token resolves to a dark-
/// or light-mode value via `NSColor(name:dynamicProvider:)` — SwiftUI
/// re-evaluates the underlying `NSColor` against the current `NSAppearance`
/// on every render, so tokens flip automatically when the system
/// appearance changes.
///
/// **Invariant:** never apply `.opacity(...)` to a `Theme.*` token at a
/// call site. Bake the alpha into the token's provider so both appearances
/// can tune it independently. Applying `.opacity(0.7)` to `Color.secondary`
/// was the pattern that broke light mode — we explicitly reject it here.
///
/// To add a new token: pick a semantic name, define the dark and light
/// values, and wrap in `makeDynamic(name:...)` below.
public enum Theme {
    // MARK: Text

    /// Primary text — system label color on both appearances (auto-adapts).
    public static let textPrimary = makeDynamic(name: "textPrimary") { _ in
        NSColor.labelColor
    }

    /// Secondary text — system `secondaryLabelColor` in both modes (itself
    /// adaptive: ~68% white on dark, ~50% black on light). Matches the grey
    /// Spotlight uses for subtitles. See the plan doc for tuning history.
    public static let textSecondary = makeDynamic(name: "textSecondary") { _ in
        NSColor.secondaryLabelColor
    }

    /// Tertiary text — system `tertiaryLabelColor` in both modes (adaptive
    /// light grey on white, adaptive dim white on dark).
    public static let textTertiary = makeDynamic(name: "textTertiary") { _ in
        NSColor.tertiaryLabelColor
    }

    /// Primary text at slight dim — used where a row wants primary emphasis
    /// but one notch quieter (e.g., RecallResultRowView body + role tag).
    /// Note: `withAlphaComponent(0.85)` replaces alpha (doesn't multiply),
    /// so this resolves to exactly 0.85 regardless of `labelColor`'s base.
    public static let textPrimaryDimmed = makeDynamic(name: "textPrimaryDimmed") { appearance in
        appearance.isDarkMode
            ? NSColor.labelColor.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.80)
    }

    // MARK: Surface overlays

    /// Row selection tint — accent blue in both modes. `controlAccentColor`
    /// is itself adaptive, so the alpha can stay constant.
    public static let selectionTint = makeDynamic(name: "selectionTint") { _ in
        NSColor.controlAccentColor.withAlphaComponent(0.20)
    }

    /// NSColor backing for `hudBorder`. Use this when you need a `CGColor`
    /// for a `CALayer`. The Color flavor wraps this NSColor.
    public static let hudBorderNSColor: NSColor = NSColor(name: NSColor.Name("hudBorder")) { appearance in
        appearance.isDarkMode
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.12)
    }

    public static let hudBorder: Color = Color(nsColor: hudBorderNSColor)

    /// NSColor backing for `panelLightTintOverlay`. Transparent in dark,
    /// white @ 0.40 in light — painted on top of the frosted `.popover`
    /// material to bleach the panel surface toward white.
    public static let panelLightTintOverlayNSColor: NSColor = NSColor(name: NSColor.Name("panelLightTintOverlay")) { appearance in
        appearance.isDarkMode
            ? NSColor.clear
            : NSColor.white.withAlphaComponent(0.40)
    }

    public static let panelLightTintOverlay: Color = Color(nsColor: panelLightTintOverlayNSColor)

    // MARK: Semantic labels

    /// Non-standard directory label (cyan family). On light mode the
    /// stock system cyan is too pale; we drop to a denser cyan at full
    /// alpha. Hex is roughly teal-cyan so it stays recognizable as the
    /// cyan lane.
    public static let directoryLabel = makeDynamic(name: "directoryLabel") { appearance in
        appearance.isDarkMode
            ? NSColor.systemCyan.withAlphaComponent(0.70)
            : NSColor(red: 0.00, green: 0.45, blue: 0.60, alpha: 1.0)
    }

    /// Stale status color (for sessions marked stale in the sidebar).
    /// `gray @ 0.5` vanishes on white, so light mode uses black @ 0.35
    /// which reads as "dimmed gray" but stays visible.
    public static let statusStale = makeDynamic(name: "statusStale") { appearance in
        appearance.isDarkMode
            ? NSColor.gray.withAlphaComponent(0.50)
            : NSColor.black.withAlphaComponent(0.35)
    }

    // MARK: Search highlighting

    /// Current search-match highlight. Orange at lower alpha on light so
    /// it doesn't burn on a white panel.
    public static let searchHighlightCurrent = makeDynamic(name: "searchHighlightCurrent") { appearance in
        appearance.isDarkMode
            ? NSColor.systemOrange.withAlphaComponent(0.60)
            : NSColor.systemOrange.withAlphaComponent(0.45)
    }

    /// Other search matches. Yellow at 0.25 is invisible on white, so
    /// light mode bumps to 0.50.
    public static let searchHighlightOther = makeDynamic(name: "searchHighlightOther") { appearance in
        appearance.isDarkMode
            ? NSColor.systemYellow.withAlphaComponent(0.25)
            : NSColor.systemYellow.withAlphaComponent(0.50)
    }

    // MARK: Accent washes

    /// Faint accent background used by the search bar and user-turn
    /// background. Bumped on light mode since a 0.06 blue wash is
    /// imperceptible on near-white.
    public static let faintAccentBackground = makeDynamic(name: "faintAccentBackground") { appearance in
        appearance.isDarkMode
            ? NSColor.controlAccentColor.withAlphaComponent(0.06)
            : NSColor.controlAccentColor.withAlphaComponent(0.10)
    }

    // MARK: Badges / pills

    /// Unread pill fill (saturated orange). Alpha is the same on both
    /// modes — orange reads on both.
    public static let pillBackgroundUnread = makeDynamic(name: "pillBackgroundUnread") { _ in
        NSColor.systemOrange.withAlphaComponent(0.80)
    }

    /// Accent-colored badge fill (filter-active chip).
    public static let badgeBackgroundAccent = makeDynamic(name: "badgeBackgroundAccent") { _ in
        NSColor.controlAccentColor.withAlphaComponent(0.80)
    }

    /// Foreground for filled pills/badges. White reads on both saturated
    /// orange and saturated accent, so the same value in both modes.
    public static let pillForeground = makeDynamic(name: "pillForeground") { _ in
        NSColor.white
    }

    // MARK: Banners

    /// Sign-in banner background at a given tint. Dark mode keeps the
    /// existing 0.12; light mode bumps to 0.18 so faint banners don't
    /// vanish on white.
    public static func bannerBackground(tint: Color) -> Color {
        makeDynamic(name: nil) { appearance in
            NSColor(tint).withAlphaComponent(appearance.isDarkMode ? 0.12 : 0.18)
        }
    }

    // MARK: Status halos

    /// Halo alpha for `AnimatedStatusDot`'s animated rings. Light mode
    /// bumps alphas modestly so the pulses still read on the whitened
    /// panel; dark mode keeps the original values so the status dots
    /// look identical to pre-plan behavior.
    public enum StatusHaloLevel: Sendable {
        case outer     // outermost pulsing ring
        case inner     // second pulsing ring
        case shadow    // glow around the main dot
    }

    /// Resolve the halo alpha for the given level and `ColorScheme`
    /// (obtained from `@Environment(\.colorScheme)` at the call site).
    /// Kept as a pure lookup so the view body can call it inline.
    public static func statusHaloAlpha(
        _ level: StatusHaloLevel,
        colorScheme: ColorScheme
    ) -> Double {
        let isDark = (colorScheme == .dark)
        switch level {
        case .outer:  return isDark ? 0.40 : 0.50
        case .inner:  return isDark ? 0.25 : 0.35
        case .shadow: return isDark ? 0.80 : 0.85
        }
    }

    // MARK: Row state

    /// Opacity applied to a row's chat-preview column based on read state.
    /// Unread rows always at 1.0. Read rows fade so the row recedes — on
    /// dark mode the historic 0.6 reads fine (white-on-dark fades to grey),
    /// but on light mode 0.6 compounds with primary near-black into a
    /// washed-out grey, so light bumps to 0.78 to keep preview text
    /// clearly readable. Pure function — call from inside view bodies
    /// using `@Environment(\.colorScheme)`.
    public static func readPreviewOpacity(
        isUnread: Bool,
        colorScheme: ColorScheme
    ) -> Double {
        if isUnread { return 1.0 }
        return colorScheme == .dark ? 0.6 : 0.78
    }

    // MARK: Status indicators

    /// Idle / connected dot. Dark mode: SwiftUI `Color.green` (= pure
    /// RGB green, which we keep for the saturated HUD look). Light mode:
    /// a darker forest green so the small 8pt dot doesn't read as
    /// blinding-bright against the whitened panel.
    public static let statusIdle = makeDynamic(name: "statusIdle") { appearance in
        appearance.isDarkMode
            ? NSColor.green
            : NSColor(red: 0.15, green: 0.50, blue: 0.25, alpha: 1.0)
    }

    /// Working / pending dot. Light: burnt-orange (RGB 0.78,0.42,0.08).
    public static let statusWorking = makeDynamic(name: "statusWorking") { appearance in
        appearance.isDarkMode
            ? NSColor.orange
            : NSColor(red: 0.78, green: 0.42, blue: 0.08, alpha: 1.0)
    }

    /// Waiting dot. Light: deep navy-blue (RGB 0.10,0.38,0.72).
    public static let statusWaiting = makeDynamic(name: "statusWaiting") { appearance in
        appearance.isDarkMode
            ? NSColor.blue
            : NSColor(red: 0.10, green: 0.38, blue: 0.72, alpha: 1.0)
    }

    /// Canceled / error dot. Light: burgundy (RGB 0.62,0.18,0.15).
    public static let statusCanceled = makeDynamic(name: "statusCanceled") { appearance in
        appearance.isDarkMode
            ? NSColor.red
            : NSColor(red: 0.62, green: 0.18, blue: 0.15, alpha: 1.0)
    }

    /// Unread accent bar — used by `SessionRowView` /
    /// `RemoteClaudeCodeRowView` as the leading bar fill when per-repo
    /// color coding is off. Same hue family as `statusWorking` so the
    /// "needs attention" signal stays consistent.
    public static let unreadAccent = makeDynamic(name: "unreadAccent") { appearance in
        appearance.isDarkMode
            ? NSColor.orange
            : NSColor(red: 0.78, green: 0.42, blue: 0.08, alpha: 1.0)
    }

    // MARK: Helpers

    /// Wrap a dynamic provider as a SwiftUI `Color`. The name is optional
    /// and is currently used only for debugging / Instruments — SwiftUI
    /// doesn't surface it in the rendered output.
    internal static func makeDynamic(
        name: String?,
        provider: @escaping (NSAppearance) -> NSColor
    ) -> Color {
        let colorName: NSColor.Name? = name.map { NSColor.Name($0) }
        return Color(nsColor: NSColor(name: colorName, dynamicProvider: provider))
    }
}
