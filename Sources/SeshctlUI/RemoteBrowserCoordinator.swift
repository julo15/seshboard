import AppKit
import Foundation
import SeshctlCore

/// Coordinates the open / navigate / focus dance for remote (cloud) Claude
/// Code sessions in a real browser. Holds a `ManagedTab` reference to the
/// tab seshctl most recently opened, so subsequent flips between sessions
/// can REUSE that tab (mutating its URL) instead of accumulating one tab
/// per session.
///
/// Identity safety: the managed tab is identified by its native browser
/// identifier (Chrome integer id / Arc UUID / Safari `(windowId, URL)`)
/// captured at AppleScript `make new tab` time. Tabs the user opened
/// manually are NEVER tracked or mutated by this coordinator — they can
/// only be matched in step 1 (focus by URL) which does not change tracking
/// and does not mutate the tab.
///
/// One instance per seshctl process; owned by `AppDelegate`. Tests
/// instantiate per-test so there is no shared static state and no
/// parallel-test race.
public final class RemoteBrowserCoordinator {
    private var managedTab: ManagedTab?

    public init() {}

    /// Three-step decision:
    /// 1. Probe browsers for any tab whose URL contains the new session id.
    ///    If found, focus it. Tracking unchanged.
    /// 2. If we have a tracked managed tab, run the navigate-by-id script
    ///    against THAT tab. On hit, mutate URL and update tracked URL. On
    ///    miss, clear tracking and fall through.
    /// 3. Create a new tab via AppleScript in the user's default browser
    ///    (if supported) and capture the new tab's identifier as our
    ///    managed tab. If the default isn't supported, fall through to
    ///    `env.openURL(url)` with no tracking.
    public func openOrFocus(url: URL, environment: SystemEnvironment? = nil) {
        openOrFocus(url: url, environment: environment, defaultBrowser: BrowserController.defaultBrowser())
    }

    // MARK: - Internals (exposed for tests via parameter injection)

    /// Test seam. Tests pass `defaultBrowser:` directly so they do not
    /// depend on the host's LaunchServices configuration.
    func openOrFocus(url: URL, environment: SystemEnvironment?, defaultBrowser: BrowserApp?) {
        let env = environment ?? TerminalController.environment

        // Step 1: focus any existing tab matching the new URL.
        let order = BrowserController.probeOrder(env: env, defaultBrowser: defaultBrowser)
        if !order.isEmpty {
            let focusScript = BrowserController.buildCombinedFocusScript(
                order: order,
                matcher: BrowserController.deriveMatcher(from: url)
            )
            if let output = env.runAppleScriptCapturingOutput(focusScript), output == "found" {
                return
            }
        }

        // Step 2: navigate our tracked tab by identifier.
        if let tracked = managedTab {
            let navScript = BrowserController.buildNavigateByIdScript(
                identifier: tracked.identifier,
                newURL: url
            )
            if let output = env.runAppleScriptCapturingOutput(navScript), output == "navigated" {
                managedTab = ManagedTab(browser: tracked.browser, identifier: tracked.identifier, url: url)
                return
            }
            // Tab is gone (closed, browser quit, dragged to a place we can't
            // reach, etc.). Clear tracking and fall through.
            managedTab = nil
        }

        // Step 3: create a new tab and track it.
        if let browser = defaultBrowser {
            let openScript = BrowserController.buildOpenTabScript(for: browser, url: url)
            if let output = env.runAppleScriptCapturingOutput(openScript),
               let parsed = Self.parseOpenTabOutput(output, fallbackURL: url) {
                managedTab = parsed
                return
            }
            // Open script failed (browser refused, parse error, etc.) — fall
            // through to NSWorkspace as the safety net.
        }

        env.openURL(url)
    }

    /// Test seam: peek at the managed-tab record. Tests assert on this to
    /// verify state transitions across `openOrFocus` calls.
    var trackedManagedTabForTesting: ManagedTab? { managedTab }

    /// Parse the stdout of `BrowserController.buildOpenTabScript`. Each
    /// browser emits a distinct format:
    ///   `"chrome:<int>"`
    ///   `"arc:<uuid-string>"`
    ///   `"safari:<int>|<url>"`
    /// Returns `nil` for unrecognized or malformed input. The `fallbackURL`
    /// is stored on the resulting `ManagedTab.url` so that `managedTab.url`
    /// is always the URL we last set on the tab (helpful for diagnostics
    /// and the Safari navigate path).
    static func parseOpenTabOutput(_ s: String, fallbackURL: URL) -> ManagedTab? {
        guard let colonIdx = s.firstIndex(of: ":") else { return nil }
        let browserToken = String(s[..<colonIdx])
        let payload = String(s[s.index(after: colonIdx)...])
        switch browserToken {
        case "chrome":
            guard let id = Int(payload) else { return nil }
            return ManagedTab(browser: .chrome, identifier: .chrome(tabId: id), url: fallbackURL)
        case "arc":
            guard !payload.isEmpty else { return nil }
            return ManagedTab(browser: .arc, identifier: .arc(tabId: payload), url: fallbackURL)
        case "safari":
            // Payload format: "<windowId>|<url>"
            guard let pipeIdx = payload.firstIndex(of: "|") else { return nil }
            let windowIdStr = String(payload[..<pipeIdx])
            let urlStr = String(payload[payload.index(after: pipeIdx)...])
            guard let windowId = Int(windowIdStr), let url = URL(string: urlStr) else { return nil }
            return ManagedTab(browser: .safari, identifier: .safari(windowId: windowId, url: url), url: url)
        default:
            return nil
        }
    }
}
