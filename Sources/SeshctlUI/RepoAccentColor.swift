import AppKit
import SwiftUI
import SeshctlCore

/// Returns a stable accent color for a repository, derived by hashing the
/// repo name into a curated palette. Used to tint the per-row accent bar,
/// the worktree/dir label, the git branch token (when no dir label is
/// present), and the tree-view group-header dot, so sessions from the
/// same repo visually cluster across local and remote rows.
///
/// Returns `nil` for `nil`/empty input so callers can fall back to their
/// default foreground style — rows without a repo identity (e.g., non-git
/// directories) stay unstyled rather than picking an arbitrary color.
public func repoAccentColor(for name: String?) -> Color? {
    guard let name, !name.isEmpty else { return nil }
    let index = Int(StableHash.djb2(name) % UInt64(repoAccentPalette.count))
    return repoAccentPalette[index]
}

/// Curated 10-color palette. Hues chosen to stay clear of existing color
/// semantics on a session row:
///   - status dots (orange/blue/green/red)   — AnimatedStatusDot, StatusKind
///   - non-standard dir label (cyan)         — SessionRowView, SessionDetailView
///   - assistant role (#937CBF purple)       — RoleColors.assistantPurple
///   - unread pill (orange)                  — UnreadPill
///
/// Saturation ~0.45–0.60 and brightness ~0.78–0.88 keep the dark-mode
/// tints readable on a dark background without overpowering the
/// semibold-monospaced repo name.
///
/// The palette is adaptive: each of the 10 slots carries both a dark-mode
/// and a light-mode value in the same hue family. The light-mode siblings
/// drop to brightness ~0.35–0.55 so the 2-pt accent bar stays readable on
/// the whitened light-mode panel. The indexing contract
/// (`djb2(name) % 10`) is unchanged — the same repo always lands in the
/// same slot; only the resolved RGB differs per appearance.
let repoAccentPalette: [Color] = [
    // 0: soft peach (0.93,0.66,0.49) / burnt sienna (0.65,0.35,0.20)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.0")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.93, green: 0.66, blue: 0.49, alpha: 1.0)
            : NSColor(red: 0.65, green: 0.35, blue: 0.20, alpha: 1.0)
    }),
    // 1: dusty rose (0.85,0.64,0.67) / wine (0.60,0.30,0.38)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.1")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.85, green: 0.64, blue: 0.67, alpha: 1.0)
            : NSColor(red: 0.60, green: 0.30, blue: 0.38, alpha: 1.0)
    }),
    // 2: warm amber (0.83,0.73,0.53) / caramel (0.58,0.45,0.18)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.2")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.83, green: 0.73, blue: 0.53, alpha: 1.0)
            : NSColor(red: 0.58, green: 0.45, blue: 0.18, alpha: 1.0)
    }),
    // 3: sage (0.64,0.78,0.62) / forest green (0.28,0.52,0.30)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.3")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.64, green: 0.78, blue: 0.62, alpha: 1.0)
            : NSColor(red: 0.28, green: 0.52, blue: 0.30, alpha: 1.0)
    }),
    // 4: slate teal (0.51,0.74,0.74) / deep teal (0.15,0.45,0.50)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.4")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.51, green: 0.74, blue: 0.74, alpha: 1.0)
            : NSColor(red: 0.15, green: 0.45, blue: 0.50, alpha: 1.0)
    }),
    // 5: saffron gold (0.95,0.74,0.35) / mustard (0.65,0.45,0.10)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.5")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.95, green: 0.74, blue: 0.35, alpha: 1.0)
            : NSColor(red: 0.65, green: 0.45, blue: 0.10, alpha: 1.0)
    }),
    // 6: mauve (0.81,0.62,0.76) / plum (0.50,0.25,0.48)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.6")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.81, green: 0.62, blue: 0.76, alpha: 1.0)
            : NSColor(red: 0.50, green: 0.25, blue: 0.48, alpha: 1.0)
    }),
    // 7: terracotta (0.86,0.58,0.50) / brick (0.55,0.25,0.20)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.7")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.86, green: 0.58, blue: 0.50, alpha: 1.0)
            : NSColor(red: 0.55, green: 0.25, blue: 0.20, alpha: 1.0)
    }),
    // 8: muted gold (0.80,0.80,0.50) / olive (0.48,0.45,0.15)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.8")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.80, green: 0.80, blue: 0.50, alpha: 1.0)
            : NSColor(red: 0.48, green: 0.45, blue: 0.15, alpha: 1.0)
    }),
    // 9: cool mint (0.62,0.83,0.74) / pine (0.15,0.50,0.40)
    Color(nsColor: NSColor(name: NSColor.Name("repoAccentPalette.9")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0.62, green: 0.83, blue: 0.74, alpha: 1.0)
            : NSColor(red: 0.15, green: 0.50, blue: 0.40, alpha: 1.0)
    }),
]
