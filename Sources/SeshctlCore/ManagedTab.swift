import Foundation

/// A browser tab that seshctl created and is currently tracking. Used by the
/// remote-session flow so that flipping between sessions reuses the same
/// physical tab (mutating its URL) instead of creating a new one each time.
///
/// Identity = `(browser, url)`. We look up "our" tab on the next flip by
/// finding the tab whose URL still contains the substring of the URL we
/// last set on it. This is robust across Arc's Little-Arc → main-window
/// promotion (which reassigns numeric tab ids) and across browser tab
/// drag-between-windows. The only ambiguity is if the user has manually
/// opened a tab at the exact same Claude session URL — accepted risk.
public struct ManagedTab: Equatable, Sendable {
    public let browser: BrowserApp
    public let url: URL

    public init(browser: BrowserApp, url: URL) {
        self.browser = browser
        self.url = url
    }
}
