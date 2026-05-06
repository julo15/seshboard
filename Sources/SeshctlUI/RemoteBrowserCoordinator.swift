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

        // Step 2: navigate our tracked tab by URL match against the URL we
        // last set on it. URL is stable across Arc's Little-Arc → main-window
        // promotion and across tab drag-between-windows; per-browser numeric
        // ids are not.
        if let tracked = managedTab {
            let navScript = BrowserController.buildNavigateScript(
                browser: tracked.browser,
                oldURL: tracked.url,
                newURL: url
            )
            if let output = env.runAppleScriptCapturingOutput(navScript), output == "navigated" {
                managedTab = ManagedTab(browser: tracked.browser, url: url)
                return
            }
            // Tab is gone (closed, browser quit, URL was manually changed
            // away from what we set). Clear tracking and fall through.
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
    /// browser emits `"<browser>:ok"` on success. Returns `nil` for
    /// unrecognized or malformed input. The resulting `ManagedTab.url` is
    /// the URL we just set on the new tab — used as the lookup key on
    /// subsequent flips.
    static func parseOpenTabOutput(_ s: String, fallbackURL: URL) -> ManagedTab? {
        guard let colonIdx = s.firstIndex(of: ":") else { return nil }
        let browserToken = String(s[..<colonIdx])
        let payload = String(s[s.index(after: colonIdx)...])
        guard payload == "ok" else { return nil }
        switch browserToken {
        case "chrome":
            return ManagedTab(browser: .chrome, url: fallbackURL)
        case "arc":
            return ManagedTab(browser: .arc, url: fallbackURL)
        case "safari":
            return ManagedTab(browser: .safari, url: fallbackURL)
        default:
            return nil
        }
    }
}
