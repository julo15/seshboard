import AppKit
import Foundation
import SeshctlCore

/// All browser-tab focusing goes through this type. It is to browsers what
/// `TerminalController` is to terminals: a thin macOS-automation layer between
/// `SessionAction` and the system AppleScript / NSWorkspace APIs.
///
/// Used today only for remote (cloud) Claude Code sessions whose `webUrl` is
/// `https://claude.ai/code/session_<UUID>`. We probe running browsers for an
/// existing tab matching the session identifier and focus it; if no browser
/// has the tab open, we fall back to `env.openURL(url)` — i.e. the user's
/// default browser opens a new tab (the pre-existing behavior).
public enum BrowserController {
    /// Try to focus an existing browser tab whose URL contains the session
    /// identifier from `url`. If no running browser matches, fall back to
    /// `env.openURL(url)`.
    public static func focusOrOpen(url: URL, environment: SystemEnvironment? = nil) {
        let env = environment ?? TerminalController.environment
        let matcher = deriveMatcher(from: url)
        for app in probeOrder(env: env) {
            if tryFocusInBrowser(app, matcher: matcher, env: env) {
                return
            }
        }
        env.openURL(url)
    }

    // MARK: - Internals (exposed for tests)

    /// Probe order: default browser first (if it's one of our supported set
    /// AND is currently running), then the remaining running browsers in
    /// `BrowserApp.allCases` declaration order. Non-running browsers are
    /// skipped entirely so we never launch a quiescent browser just to probe.
    static func probeOrder(env: SystemEnvironment) -> [BrowserApp] {
        let running = Set(env.runningAppBundleIds())
        let runningBrowsers = BrowserApp.allCases.filter { running.contains($0.bundleId) }
        guard let preferred = defaultBrowser(), runningBrowsers.contains(preferred) else {
            return runningBrowsers
        }
        return [preferred] + runningBrowsers.filter { $0 != preferred }
    }

    /// Closure used by `defaultBrowser()` to resolve the user's default
    /// browser. Tests can override this to drive `probeOrder` deterministically;
    /// production reads it via LaunchServices.
    nonisolated(unsafe) static var defaultBrowserResolver: () -> BrowserApp? = {
        guard let url = URL(string: "https://claude.ai/") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        guard let bundle = Bundle(url: appURL), let bundleId = bundle.bundleIdentifier else { return nil }
        return BrowserApp.from(bundleId: bundleId)
    }

    /// Identify the user's default browser for `https://` URLs. Returns `nil`
    /// if the default isn't one of the browsers in `BrowserApp`. Goes through
    /// `defaultBrowserResolver` so tests can swap the implementation.
    static func defaultBrowser() -> BrowserApp? {
        defaultBrowserResolver()
    }

    /// Run the per-browser AppleScript and treat stdout `"found"` as a hit.
    /// Any other output (including `nil` from a non-zero exit) means no match.
    static func tryFocusInBrowser(_ app: BrowserApp, matcher: String, env: SystemEnvironment) -> Bool {
        let script = buildFocusScript(for: app, matcher: matcher)
        guard let output = env.runAppleScriptCapturingOutput(script) else { return false }
        return output == "found"
    }

    /// Build the per-browser AppleScript. Each script:
    ///   - Wraps its body in `if application "<name>" is running` so probing
    ///     a quiescent browser is a true no-op (does not launch it).
    ///   - Walks the tab model native to that browser.
    ///   - On match: focuses the tab, raises its window, activates the app,
    ///     and returns the literal string `"found"`.
    ///   - On no match: returns the empty string.
    /// All matcher substrings flow through `TerminalController.escapeForAppleScript`
    /// to prevent injection.
    static func buildFocusScript(for app: BrowserApp, matcher: String) -> String {
        let escaped = TerminalController.escapeForAppleScript(matcher)
        let appName = app.applicationName
        switch app {
        case .chrome:
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escaped)"
                repeat with w from 1 to count of windows
                  set tabCount to count of tabs of window w
                  repeat with i from 1 to tabCount
                    if URL of tab i of window w contains targetMatcher then
                      set active tab index of window w to i
                      set index of window w to 1
                      activate
                      return "found"
                    end if
                  end repeat
                end repeat
              end tell
            end if
            return ""
            """
        case .arc:
            // Arc's tab model lives under `spaces` (sidebar). Wrap in `try`
            // so windows without spaces (Little Arc popovers) silently skip
            // rather than aborting the whole script.
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escaped)"
                repeat with w in windows
                  try
                    repeat with sp in spaces of w
                      repeat with t in tabs of sp
                        if URL of t contains targetMatcher then
                          tell t to select
                          activate
                          return "found"
                        end if
                      end repeat
                    end repeat
                  end try
                end repeat
              end tell
            end if
            return ""
            """
        case .safari:
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escaped)"
                repeat with w in windows
                  repeat with t in tabs of w
                    if URL of t contains targetMatcher then
                      set current tab of w to t
                      set index of w to 1
                      activate
                      return "found"
                    end if
                  end repeat
                end repeat
              end tell
            end if
            return ""
            """
        }
    }

    /// Extract a stable matcher substring from a remote-session URL. The
    /// canonical shape is `https://claude.ai/code/session_<UUID>`; we match
    /// on `/code/session_<UUID>` to be robust against query strings, fragments,
    /// or trailing path segments. Falls back to `url.path` if the canonical
    /// suffix isn't present.
    static func deriveMatcher(from url: URL) -> String {
        let path = url.path
        if let range = path.range(of: "/code/session_") {
            return String(path[range.lowerBound...])
        }
        return path
    }
}
