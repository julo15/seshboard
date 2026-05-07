import Foundation

/// A browser tab that seshctl created and is currently tracking. Used by the
/// remote-session flow so that flipping between sessions reuses the same
/// physical tab (mutating its URL) instead of creating a new one each time.
///
/// Identity is `(browser, url)`. We re-find "our" tab on the next flip by
/// matching the substring of `url` against tab URLs in the same browser.
/// We do NOT use a per-browser tab id: Arc reassigns numeric tab ids on
/// Little-Arc → main-window promotion, Safari has no tab id at all, and
/// unifying on URL keeps the three browsers' code paths uniform.
///
/// The trade-off: a manually-opened tab at the same Claude session URL we
/// tracked CAN be navigated by the step-1 fast path if the AppleScript
/// walk finds it first. Documented and accepted.
public struct ManagedTab: Equatable, Sendable {
    public let browser: BrowserApp
    public let url: URL

    public init(browser: BrowserApp, url: URL) {
        self.browser = browser
        self.url = url
    }
}
