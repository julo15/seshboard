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

    /// Three-step decision (ordered fast-path first):
    /// 1. If we have a tracked managed tab, run the navigate script against
    ///    THAT tab. On hit, mutate URL and update tracked URL. On miss,
    ///    clear tracking and fall through. This is the common-case fast
    ///    path for flipping between remote sessions — one osascript, one
    ///    tab walk in the managed browser only.
    /// 2. (Slow path) Probe ALL running browsers for any tab whose URL
    ///    contains the new session id. Reached only when we don't have a
    ///    tracked tab or the tracked tab was lost.
    /// 3. Create a new tab via AppleScript in the user's default browser
    ///    (if supported) and capture the new tab's URL as the managed
    ///    tab. If the default isn't supported, fall through to
    ///    `env.openURL(url)` with no tracking.
    public func openOrFocus(url: URL, environment: SystemEnvironment? = nil) {
        openOrFocus(url: url, environment: environment, defaultBrowser: BrowserController.defaultBrowser())
    }

    // MARK: - Internals (exposed for tests via parameter injection)

    /// Test seam. Tests pass `defaultBrowser:` directly so they do not
    /// depend on the host's LaunchServices configuration.
    func openOrFocus(url: URL, environment: SystemEnvironment?, defaultBrowser: BrowserApp?) {
        let env = environment ?? TerminalController.environment

        // Step 1 (fast path): if we have a tracked managed tab, navigate it
        // directly. This is the common case for flipping between remote
        // sessions and skips the all-browsers focus probe — which would
        // otherwise walk every tab of every space of every window in every
        // running browser. Saves one osascript invocation and one full tab
        // walk per flip when there's a tracked tab.
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
            // away from what we set). Clear tracking and fall through to
            // the slower probe path.
            managedTab = nil
        }

        // Step 2: focus any existing tab matching the new URL (across all
        // running browsers). Reached only when we don't have a tracked tab,
        // OR the tracked tab is gone.
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

        // Step 3: create a new tab and track it.
        if let browser = defaultBrowser {
            let openScript = BrowserController.buildOpenTabScript(for: browser, url: url)
            if let output = env.runAppleScriptCapturingOutput(openScript),
               let parsed = Self.parseOpenTabOutput(output, fallbackURL: url) {
                managedTab = parsed
                return
            }
            // Open script failed (browser refused, parse error) — fall
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
