import AppKit
import Foundation
import SeshctlCore

/// All browser-tab focusing goes through this type. It is to browsers what
/// `TerminalController` is to terminals: a thin macOS-automation layer between
/// `SessionAction` and the system AppleScript / NSWorkspace APIs.
///
/// Used today only for remote (cloud) Claude Code sessions whose `webUrl` is
/// `https://claude.ai/code/session_<UUID>`. We probe running browsers (in
/// default-first order) for an existing tab matching the session identifier
/// and focus it; if no browser has the tab open, we fall back to
/// `env.openURL(url)` — i.e. the user's default browser opens a new tab
/// (the pre-existing behavior).
public enum BrowserController {
    /// Try to focus an existing browser tab whose URL contains the session
    /// identifier from `url`. If no running browser matches, fall back to
    /// `env.openURL(url)`.
    ///
    /// All running browsers are checked in a SINGLE `osascript` invocation —
    /// the script visits each browser in probe order and short-circuits on
    /// first match. This keeps wall-clock latency low when multiple browsers
    /// are running.
    public static func focusOrOpen(url: URL, environment: SystemEnvironment? = nil) {
        focusOrOpen(url: url, environment: environment, defaultBrowser: defaultBrowser())
    }

    // MARK: - Internals (exposed for tests via parameter injection)

    /// Test seam for `focusOrOpen`. Tests pass `defaultBrowser:` directly so
    /// they don't depend on the host's LaunchServices configuration.
    static func focusOrOpen(url: URL, environment: SystemEnvironment?, defaultBrowser: BrowserApp?) {
        let env = environment ?? TerminalController.environment
        let order = probeOrder(env: env, defaultBrowser: defaultBrowser)
        if !order.isEmpty {
            let script = buildCombinedFocusScript(order: order, matcher: deriveMatcher(from: url))
            if let output = env.runAppleScriptCapturingOutput(script), output == "found" {
                return
            }
        }
        env.openURL(url)
    }

    /// Probe order: default browser first (if one of our supported set AND
    /// currently running), then the remaining running browsers in
    /// `BrowserApp.allCases` declaration order. Non-running browsers are
    /// excluded entirely so we never launch a quiescent browser just to probe.
    static func probeOrder(env: SystemEnvironment, defaultBrowser: BrowserApp?) -> [BrowserApp] {
        let running = Set(env.runningAppBundleIds())
        let runningBrowsers = BrowserApp.allCases.filter { running.contains($0.bundleId) }
        guard let preferred = defaultBrowser, runningBrowsers.contains(preferred) else {
            return runningBrowsers
        }
        return [preferred] + runningBrowsers.filter { $0 != preferred }
    }

    /// Identify the user's default browser for `https://` URLs via LaunchServices.
    /// Returns `nil` if the default isn't one of the browsers in `BrowserApp`.
    static func defaultBrowser() -> BrowserApp? {
        guard let url = URL(string: "https://claude.ai/") else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        guard let bundle = Bundle(url: appURL), let bundleId = bundle.bundleIdentifier else { return nil }
        return BrowserApp.from(bundleId: bundleId)
    }

    /// Build a combined AppleScript that probes each browser in `order` in turn —
    /// first match wins. Returns `"found"` on a hit, empty string otherwise.
    /// Each block is wrapped in its own `if application "<name>" is running`
    /// guard so this script is safe to dispatch even if a browser quits between
    /// when we polled `runningAppBundleIds()` and when osascript actually fires
    /// Apple Events (the guard prevents `tell application "X"` from launching
    /// the app).
    static func buildCombinedFocusScript(order: [BrowserApp], matcher: String) -> String {
        let escaped = TerminalController.escapeForAppleScript(matcher)
        var lines: [String] = order.map { buildFocusBlock(for: $0, escapedMatcher: escaped) }
        lines.append("return \"\"")
        return lines.joined(separator: "\n")
    }

    /// One-browser convenience. Equivalent to a combined script with a single
    /// browser in the order. Returns `"found"` on match, `""` otherwise.
    static func buildFocusScript(for app: BrowserApp, matcher: String) -> String {
        buildCombinedFocusScript(order: [app], matcher: matcher)
    }

    /// Build the per-browser block. Each block:
    ///   - Wraps its body in `if application "<name>" is running` so it does
    ///     not launch the app if it isn't already running.
    ///   - Walks the tab model native to that browser.
    ///   - On match: focuses the tab, raises its window, activates the app,
    ///     and returns the literal string `"found"` from the enclosing script.
    /// Caller is responsible for escaping the matcher and appending a final
    /// `return ""` to the assembled script.
    static func buildFocusBlock(for app: BrowserApp, escapedMatcher: String) -> String {
        let appName = app.applicationName
        switch app {
        case .chrome:
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escapedMatcher)"
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
            """
        case .arc:
            // Arc's tab model lives under `spaces` (sidebar). Wrap in `try` so
            // windows without spaces (Little Arc popovers) silently skip rather
            // than aborting the whole script.
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escapedMatcher)"
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
            """
        case .safari:
            return """
            if application "\(appName)" is running then
              tell application "\(appName)"
                set targetMatcher to "\(escapedMatcher)"
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
            """
        }
    }

    /// Build an AppleScript that creates a new tab in `app` at `url`, focuses
    /// it, and returns a parseable identifier on stdout. Output format:
    /// `"chrome:<tabId>"`, `"arc:<tabId>"`, or `"safari:<windowId>|<url>"`.
    /// The caller (`RemoteBrowserCoordinator`) parses this into a `ManagedTab`
    /// so future flips can navigate THIS specific tab by id rather than by
    /// URL match (which can't distinguish ours from a user-opened tab).
    ///
    /// For Arc we deliberately do NOT specify a window — Arc places the new
    /// tab in the active workspace, sidestepping Little Arc popovers.
    static func buildOpenTabScript(for app: BrowserApp, url: URL) -> String {
        let escapedURL = TerminalController.escapeForAppleScript(url.absoluteString)
        let appName = app.applicationName
        switch app {
        case .chrome:
            return """
            tell application "\(appName)"
              set newTab to make new tab at end of tabs of front window with properties {URL:"\(escapedURL)"}
              set index of front window to 1
              activate
              return "chrome:" & (id of newTab as text)
            end tell
            """
        case .arc:
            // `make new tab` without a target lands in Little Arc (a popover
            // window with zero spaces). Target a normal Arc window — one with
            // at least one space — so the new tab lands in the sidebar where
            // it can be reused on subsequent flips. Fall back to default
            // placement if no normal window exists (the result will be a
            // Little Arc but at least it gets created and tracked).
            return """
            tell application "\(appName)"
              set normalWindow to missing value
              repeat with w in windows
                try
                  if (count of spaces of w) > 0 then
                    set normalWindow to w
                    exit repeat
                  end if
                end try
              end repeat
              if normalWindow is missing value then
                set newTab to make new tab with properties {URL:"\(escapedURL)"}
              else
                set newTab to make new tab at end of tabs of normalWindow with properties {URL:"\(escapedURL)"}
              end if
              activate
              return "arc:" & (id of newTab as text)
            end tell
            """
        case .safari:
            return """
            tell application "\(appName)"
              set newTab to make new tab at end of tabs of front window with properties {URL:"\(escapedURL)"}
              set current tab of front window to newTab
              set index of front window to 1
              activate
              return "safari:" & (id of front window as text) & "|" & "\(escapedURL)"
            end tell
            """
        }
    }

    /// Build an AppleScript that finds a previously-tracked tab BY IDENTIFIER
    /// and mutates its URL to `newURL`. Returns `"navigated"` on hit, empty
    /// string otherwise (so the caller can fall through to opening a new tab).
    ///
    /// Identifier-based lookup is the key safety property: we only ever
    /// mutate tabs whose identity we captured at creation time. User-opened
    /// tabs (which we never tracked) cannot be reached by this script even
    /// if their URL matches what we previously opened.
    ///
    /// Each block is wrapped in `if application "X" is running` so the script
    /// is safe to dispatch even if the browser has quit (the guard prevents
    /// `tell application` from launching the app).
    static func buildNavigateByIdScript(identifier: TabIdentifier, newURL: URL) -> String {
        let escapedNewURL = TerminalController.escapeForAppleScript(newURL.absoluteString)
        switch identifier {
        case .chrome(let tabId):
            return """
            if application "Google Chrome" is running then
              tell application "Google Chrome"
                set targetId to \(tabId)
                repeat with w in windows
                  set tabIdx to 0
                  repeat with t in tabs of w
                    set tabIdx to tabIdx + 1
                    if (id of t) is targetId then
                      set URL of t to "\(escapedNewURL)"
                      set active tab index of w to tabIdx
                      set index of w to 1
                      activate
                      return "navigated"
                    end if
                  end repeat
                end repeat
              end tell
            end if
            return ""
            """
        case .arc(let tabId):
            let escapedId = TerminalController.escapeForAppleScript(tabId)
            // Walk both spaces (normal Arc) and direct window tabs (Little Arc fallback).
            return """
            if application "Arc" is running then
              tell application "Arc"
                set targetId to "\(escapedId)"
                repeat with w in windows
                  try
                    repeat with sp in spaces of w
                      repeat with t in tabs of sp
                        if (id of t) is targetId then
                          set URL of t to "\(escapedNewURL)"
                          tell t to select
                          activate
                          return "navigated"
                        end if
                      end repeat
                    end repeat
                  end try
                  try
                    repeat with t in tabs of w
                      if (id of t) is targetId then
                        set URL of t to "\(escapedNewURL)"
                        tell t to select
                        activate
                        return "navigated"
                      end if
                    end repeat
                  end try
                end repeat
              end tell
            end if
            return ""
            """
        case .safari(let windowId, let oldURL):
            // Use the same robust matcher logic as the focus path: compare on
            // `/code/session_<id>` rather than full URL equality so we tolerate
            // Safari URL normalization (trailing slashes, fragments, etc.).
            let oldMatcher = deriveMatcher(from: oldURL)
            let escapedOldMatcher = TerminalController.escapeForAppleScript(oldMatcher)
            return """
            if application "Safari" is running then
              tell application "Safari"
                try
                  set targetWindow to window id \(windowId)
                  repeat with t in tabs of targetWindow
                    if (URL of t) contains "\(escapedOldMatcher)" then
                      set URL of t to "\(escapedNewURL)"
                      set current tab of targetWindow to t
                      set index of targetWindow to 1
                      activate
                      return "navigated"
                    end if
                  end repeat
                end try
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
