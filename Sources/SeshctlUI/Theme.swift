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
enum Theme {
    // MARK: Text

    /// Primary text — system label color on both appearances (auto-adapts).
    static let textPrimary = makeDynamic(name: "textPrimary") { appearance in
        NSColor.labelColor
    }

    /// Secondary text — on light, deeper than system .secondary (which is
    /// too faint on a near-white panel). Dark stays on system.
    static let textSecondary = makeDynamic(name: "textSecondary") { appearance in
        appearance.isDarkMode
            ? NSColor.secondaryLabelColor
            : NSColor.black.withAlphaComponent(0.78)
    }

    /// Tertiary text — same rationale as textSecondary but a tier lighter.
    static let textTertiary = makeDynamic(name: "textTertiary") { appearance in
        appearance.isDarkMode
            ? NSColor.tertiaryLabelColor
            : NSColor.black.withAlphaComponent(0.58)
    }

    /// Primary text at slight dim — used where a row wants primary emphasis
    /// but one notch quieter (e.g., RecallResultRowView body + role tag).
    static let textPrimaryDimmed = makeDynamic(name: "textPrimaryDimmed") { appearance in
        appearance.isDarkMode
            ? NSColor.labelColor.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.80)
    }

    // MARK: Surface overlays

    /// Row selection tint — accent blue in both modes. `controlAccentColor`
    /// is itself adaptive, so the alpha can stay constant.
    static let selectionTint = makeDynamic(name: "selectionTint") { appearance in
        NSColor.controlAccentColor.withAlphaComponent(0.20)
    }

    /// Panel hairline border — white at low alpha on dark, black at low
    /// alpha on light. Captured on FloatingPanel as a CGColor; must be
    /// re-resolved on `viewDidChangeEffectiveAppearance`.
    static let hudBorder = makeDynamic(name: "hudBorder") { appearance in
        appearance.isDarkMode
            ? NSColor.white.withAlphaComponent(0.15)
            : NSColor.black.withAlphaComponent(0.12)
    }

    /// Overlay painted on top of the .popover material in light mode to
    /// bleach the frosted glass toward white. Transparent in dark mode.
    static let panelLightTintOverlay = makeDynamic(name: "panelLightTintOverlay") { appearance in
        appearance.isDarkMode
            ? NSColor.clear
            : NSColor.white.withAlphaComponent(0.40)
    }

    // MARK: Semantic labels

    /// Non-standard directory label (cyan family). On light mode the
    /// stock system cyan is too pale; we drop to a denser cyan at full
    /// alpha. Hex is roughly teal-cyan so it stays recognizable as the
    /// cyan lane.
    static let directoryLabel = makeDynamic(name: "directoryLabel") { appearance in
        appearance.isDarkMode
            ? NSColor.systemCyan.withAlphaComponent(0.70)
            : NSColor(red: 0.00, green: 0.45, blue: 0.60, alpha: 1.0)
    }

    /// Stale status color (for sessions marked stale in the sidebar).
    /// `gray @ 0.5` vanishes on white, so light mode uses black @ 0.35
    /// which reads as "dimmed gray" but stays visible.
    static let statusStale = makeDynamic(name: "statusStale") { appearance in
        appearance.isDarkMode
            ? NSColor.gray.withAlphaComponent(0.50)
            : NSColor.black.withAlphaComponent(0.35)
    }

    // MARK: Search highlighting

    /// Current search-match highlight. Orange at lower alpha on light so
    /// it doesn't burn on a white panel.
    static let searchHighlightCurrent = makeDynamic(name: "searchHighlightCurrent") { appearance in
        appearance.isDarkMode
            ? NSColor.systemOrange.withAlphaComponent(0.60)
            : NSColor.systemOrange.withAlphaComponent(0.45)
    }

    /// Other search matches. Yellow at 0.25 is invisible on white, so
    /// light mode bumps to 0.50.
    static let searchHighlightOther = makeDynamic(name: "searchHighlightOther") { appearance in
        appearance.isDarkMode
            ? NSColor.systemYellow.withAlphaComponent(0.25)
            : NSColor.systemYellow.withAlphaComponent(0.50)
    }

    // MARK: Accent washes

    /// Faint accent background used by the search bar and user-turn
    /// background. Bumped on light mode since a 0.06 blue wash is
    /// imperceptible on near-white.
    static let faintAccentBackground = makeDynamic(name: "faintAccentBackground") { appearance in
        appearance.isDarkMode
            ? NSColor.controlAccentColor.withAlphaComponent(0.06)
            : NSColor.controlAccentColor.withAlphaComponent(0.10)
    }

    // MARK: Badges / pills

    /// Unread pill fill (saturated orange). Alpha is the same on both
    /// modes — orange reads on both.
    static let pillBackgroundUnread = makeDynamic(name: "pillBackgroundUnread") { appearance in
        NSColor.systemOrange.withAlphaComponent(0.80)
    }

    /// Accent-colored badge fill (filter-active chip).
    static let badgeBackgroundAccent = makeDynamic(name: "badgeBackgroundAccent") { appearance in
        NSColor.controlAccentColor.withAlphaComponent(0.80)
    }

    /// Foreground for filled pills/badges. White reads on both saturated
    /// orange and saturated accent, so the same value in both modes.
    static let pillForeground = makeDynamic(name: "pillForeground") { _ in
        NSColor.white
    }

    // MARK: Banners

    /// Sign-in banner background at a given tint. Dark mode keeps the
    /// existing 0.12; light mode bumps to 0.18 so faint banners don't
    /// vanish on white.
    static func bannerBackground(tint: Color) -> Color {
        makeDynamic(name: nil) { appearance in
            NSColor(tint).withAlphaComponent(appearance.isDarkMode ? 0.12 : 0.18)
        }
    }

    // MARK: Helpers

    /// Wrap a dynamic provider as a SwiftUI `Color`. The name is optional
    /// and is currently used only for debugging / Instruments — SwiftUI
    /// doesn't surface it in the rendered output.
    private static func makeDynamic(
        name: String?,
        provider: @escaping (NSAppearance) -> NSColor
    ) -> Color {
        let colorName: NSColor.Name? = name.map { NSColor.Name($0) }
        return Color(nsColor: NSColor(name: colorName, dynamicProvider: provider))
    }
}
