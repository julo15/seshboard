import AppKit

extension NSAppearance {
    /// True if the effective appearance is any dark variant (including the
    /// accessibility high-contrast darks). Used by Theme's dynamic color
    /// providers to pick dark- vs light-mode values.
    var isDarkMode: Bool {
        bestMatch(from: [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark,
        ]) != nil
    }
}
