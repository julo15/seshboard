import AppKit
import SwiftUI

extension Color {
    /// Purple used for assistant/Claude role labels. Adaptive: the
    /// existing `#937CBF` reads on a dark HUD but muddies into a white
    /// panel, so light mode uses a denser `#6B53A0`.
    static let assistantPurple = Color(nsColor: NSColor(name: NSColor.Name("assistantPurple")) { appearance in
        appearance.isDarkMode
            ? NSColor(red: 0x93 / 255.0, green: 0x7C / 255.0, blue: 0xBF / 255.0, alpha: 1.0)
            : NSColor(red: 0x6B / 255.0, green: 0x53 / 255.0, blue: 0xA0 / 255.0, alpha: 1.0)
    })
}
