import Foundation

/// A browser tab that seshctl created and is currently tracking. Used by the
/// remote-session flow so that flipping between sessions reuses the same
/// physical tab instead of creating a new one each time.
///
/// Identity comes from `identifier`, captured at the moment the tab was
/// created via AppleScript `make new tab`. We never use URL alone to identify
/// "our" tab — that would risk hijacking a user-opened tab that happens to be
/// at the same Claude session URL.
public struct ManagedTab: Equatable, Sendable {
    public let browser: BrowserApp
    public let identifier: TabIdentifier
    public let url: URL

    public init(browser: BrowserApp, identifier: TabIdentifier, url: URL) {
        self.browser = browser
        self.identifier = identifier
        self.url = url
    }
}

/// How seshctl re-finds a managed tab on subsequent flips. Each browser's
/// AppleScript dictionary exposes a different identity primitive:
/// - Chrome and Arc both expose a stable `id` on `tab` (integer / UUID-string
///   respectively); we use it directly.
/// - Safari has no tab `id`. We track `(windowId, url)` instead — narrow to
///   the window we created the tab in, then match a tab inside that window by
///   URL substring. Vanishingly rare misidentification (would require the
///   user to have the same URL open twice in the same Safari window).
public enum TabIdentifier: Equatable, Sendable {
    case chrome(tabId: Int)
    case arc(tabId: String)
    case safari(windowId: Int, url: URL)
}
