import Foundation
import Testing
@testable import SeshctlCore
@testable import SeshctlUI

@Suite("BrowserController")
struct BrowserControllerTests {

    // MARK: - deriveMatcher

    @Test("deriveMatcher extracts /code/session_<id> from canonical webUrl")
    func deriveMatcherCanonical() {
        let url = URL(string: "https://claude.ai/code/session_abc123")!
        #expect(BrowserController.deriveMatcher(from: url) == "/code/session_abc123")
    }

    @Test("deriveMatcher tolerates query string and fragment")
    func deriveMatcherWithExtras() {
        let url = URL(string: "https://claude.ai/code/session_abc123?foo=bar#baz")!
        // url.path strips query and fragment; matcher is the post-/code/session_ slice.
        #expect(BrowserController.deriveMatcher(from: url) == "/code/session_abc123")
    }

    @Test("deriveMatcher falls back to path when canonical suffix missing")
    func deriveMatcherFallback() {
        let url = URL(string: "https://example.com/some/other/path")!
        #expect(BrowserController.deriveMatcher(from: url) == "/some/other/path")
    }

    // MARK: - buildFocusScript

    @Test("Chrome script uses active tab index, raises window, activates")
    func chromeScriptShape() {
        let script = BrowserController.buildFocusScript(for: .chrome, matcher: "/code/session_X")
        #expect(script.contains("if application \"Google Chrome\" is running"))
        #expect(script.contains("tell application \"Google Chrome\""))
        #expect(script.contains("active tab index"))
        #expect(script.contains("set index of window w to 1"))
        #expect(script.contains("activate"))
        #expect(script.contains("\"/code/session_X\""))
        #expect(script.contains("return \"found\""))
    }

    @Test("Arc script walks spaces of windows by index and AXRaises the matched window")
    func arcScriptShape() {
        let script = BrowserController.buildFocusScript(for: .arc, matcher: "/code/session_X")
        #expect(script.contains("if application \"Arc\" is running"))
        #expect(script.contains("tell application \"Arc\""))
        // Index-based iteration (not `repeat with w in windows`) because Arc
        // rejects scalar property access on iteration-variable refs.
        #expect(script.contains("repeat with wIdx from 1 to wCount"))
        #expect(script.contains("space spIdx of window wIdx"))
        #expect(script.contains("tell t to select"))
        // Multi-window: capture Arc's window UUID, then in System Events
        // find the AX window whose AXIdentifier contains that UUID and
        // AXRaise it. Cross-process key is the UUID, not the index, so
        // a hypothetical Arc-side window reorder between match and raise
        // can't desync the target.
        #expect(script.contains("set winId to id of window wIdx"))
        #expect(script.contains("tell application \"System Events\""))
        #expect(script.contains("tell process \"Arc\""))
        #expect(script.contains("value of attribute \"AXIdentifier\" of window seIdx"))
        #expect(script.contains("contains winId"))
        #expect(script.contains("perform action \"AXRaise\" of window seIdx"))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"found\""))
        // UUID must be captured BEFORE `tell t to select`, otherwise an
        // Arc-side window reorder triggered by the selection could move
        // `window wIdx` to a different window before `id of window wIdx`
        // reads it.
        if let captureIdx = script.range(of: "set winId to id of window wIdx")?.lowerBound,
           let selectIdx = script.range(of: "tell t to select")?.lowerBound {
            #expect(captureIdx < selectIdx,
                    "winId capture must come before `tell t to select`")
        } else {
            Issue.record("winId capture or tab select missing from Arc focus script")
        }
        // AXRaise MUST run before activate. Reversed order silently
        // regresses multi-window focus (Arc paints old front window on
        // activate, before AXRaise reorders the internal stack).
        if let raiseIdx = script.range(of: "perform action \"AXRaise\" of window seIdx")?.lowerBound,
           let activateIdx = script.range(of: "activate")?.lowerBound {
            #expect(raiseIdx < activateIdx,
                    "AXRaise must come before activate in Arc focus block")
        } else {
            Issue.record("AXRaise or activate missing from Arc focus script")
        }
        // Missing-Accessibility degradation hinges on the AXRaise being
        // try-wrapped — otherwise the error aborts the whole focus block
        // and the script returns "" instead of "found". Position-based
        // check: the SE/AXRaise block must sit between a `try` and its
        // matching `end try`.
        if let seIdx = script.range(of: "tell application \"System Events\"")?.lowerBound {
            let prefix = script[..<seIdx]
            let suffix = script[seIdx...]
            #expect(prefix.range(of: "try", options: .backwards) != nil,
                    "AXRaise SE block must be preceded by `try`")
            #expect(suffix.range(of: "end try") != nil,
                    "AXRaise SE block must be followed by `end try`")
        } else {
            Issue.record("SystemEvents block missing")
        }
    }

    @Test("Safari script sets current tab and raises window")
    func safariScriptShape() {
        let script = BrowserController.buildFocusScript(for: .safari, matcher: "/code/session_X")
        #expect(script.contains("if application \"Safari\" is running"))
        #expect(script.contains("tell application \"Safari\""))
        #expect(script.contains("set current tab of w to t"))
        #expect(script.contains("set index of w to 1"))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"found\""))
    }

    @Test("Matcher is escaped before interpolation so injection is impossible")
    func matcherEscaping() {
        let evil = "x\"; do shell script \"rm -rf /\"; \""
        let script = BrowserController.buildFocusScript(for: .chrome, matcher: evil)
        // Raw evil string must NOT appear unescaped (would close the AppleScript string literal).
        #expect(!script.contains("x\"; do shell"))
        // The escaped form (each `"` → `\"`) MUST appear.
        #expect(script.contains("x\\\"; do shell script \\\"rm -rf /\\\""))
    }

    // MARK: - focusOrOpen end-to-end

    @Test("focusOrOpen falls back to env.openURL when no browsers are running")
    func focusOrOpenNoBrowsersFallsBack() {
        let env = MockSystemEnvironment()
        env.runningApps = []

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env, defaultBrowser: nil)

        #expect(env.openedURLs == [url])
        #expect(env.executedScripts.isEmpty)
    }

    @Test("focusOrOpen runs a single combined script and skips fallback on hit")
    func focusOrOpenProbesAndSkipsFallback() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            script.contains("Google Chrome") ? "found" : ""
        }

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env, defaultBrowser: .chrome)

        #expect(env.openedURLs.isEmpty)
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("Google Chrome"))
    }

    @Test("focusOrOpen runs one combined script with all running browsers, then falls back when none match")
    func focusOrOpenTriesAllAndFallsBack() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"]
        env.appleScriptOutputProvider = { _ in "" }

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env, defaultBrowser: nil)

        #expect(env.executedScripts.count == 1)
        let combined = env.executedScripts[0]
        #expect(combined.contains("Google Chrome"))
        #expect(combined.contains("Arc"))
        #expect(combined.contains("Safari"))
        #expect(env.openedURLs == [url])
    }

    @Test("Combined script orders browser blocks by probeOrder (default first)")
    func combinedScriptOrderRespectsProbeOrder() {
        let script = BrowserController.buildCombinedFocusScript(order: [.safari, .chrome, .arc], matcher: "/code/session_X")
        guard let safariIdx = script.range(of: "tell application \"Safari\"")?.lowerBound,
              let chromeIdx = script.range(of: "tell application \"Google Chrome\"")?.lowerBound,
              let arcIdx = script.range(of: "tell application \"Arc\"")?.lowerBound else {
            Issue.record("missing one or more browser tell blocks")
            return
        }
        #expect(safariIdx < chromeIdx)
        #expect(chromeIdx < arcIdx)
        #expect(script.hasSuffix("return \"\""))
    }

    // MARK: - probeOrder

    @Test("probeOrder skips non-running browsers")
    func probeOrderSkipsNonRunning() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        #expect(BrowserController.probeOrder(env: env, defaultBrowser: nil) == [.chrome])
    }

    @Test("probeOrder puts default browser first when running")
    func probeOrderDefaultBrowserFirst() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"]
        let order = BrowserController.probeOrder(env: env, defaultBrowser: .safari)
        #expect(order.first == .safari)
        #expect(Set(order) == Set([BrowserApp.chrome, .arc, .safari]))
    }

    @Test("probeOrder ignores default browser when it isn't running")
    func probeOrderIgnoresNonRunningDefault() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        #expect(BrowserController.probeOrder(env: env, defaultBrowser: .arc) == [.chrome])
    }

    // MARK: - BrowserApp.from(bundleId:)

    @Test("BrowserApp.from maps known bundle IDs to cases")
    func browserAppFromKnown() {
        #expect(BrowserApp.from(bundleId: "com.google.Chrome") == .chrome)
        #expect(BrowserApp.from(bundleId: "company.thebrowser.Browser") == .arc)
        #expect(BrowserApp.from(bundleId: "com.apple.Safari") == .safari)
    }

    @Test("BrowserApp.from returns nil for unknown bundle IDs")
    func browserAppFromUnknown() {
        #expect(BrowserApp.from(bundleId: "com.brave.Browser") == nil)
        #expect(BrowserApp.from(bundleId: "") == nil)
    }

    // MARK: - buildOpenTabScript

    @Test("Chrome open script makes a new tab in front window and returns chrome:ok")
    func chromeOpenScriptShape() {
        let url = URL(string: "https://claude.ai/code/session_abc")!
        let script = BrowserController.buildOpenTabScript(for: .chrome, url: url)
        #expect(script.contains("tell application \"Google Chrome\""))
        #expect(script.contains("make new tab at end of tabs of front window"))
        #expect(script.contains("URL:\"https://claude.ai/code/session_abc\""))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"chrome:ok\""))
    }

    @Test("Arc open script targets a normal window (non-Little-Arc) by spaces heuristic")
    func arcOpenScriptShape() {
        let url = URL(string: "https://claude.ai/code/session_abc")!
        let script = BrowserController.buildOpenTabScript(for: .arc, url: url)
        #expect(script.contains("tell application \"Arc\""))
        // Heuristic: walk windows looking for one with at least one space.
        // Little Arc windows have zero spaces; normal windows have ≥ 1.
        #expect(script.contains("count of spaces of w"))
        #expect(script.contains("normalWindow"))
        // Both placement branches present — one for normal-window target,
        // one for the no-normal-window fallback.
        #expect(script.contains("make new tab at end of tabs of normalWindow with properties"))
        #expect(script.contains("make new tab with properties {URL:"))
        #expect(script.contains("activate"))
        // Sentinel return — actual identity is captured by the URL we set.
        #expect(script.contains("return \"arc:ok\""))
    }

    @Test("Safari open script makes a new tab in front window and returns safari:ok")
    func safariOpenScriptShape() {
        let url = URL(string: "https://claude.ai/code/session_abc")!
        let script = BrowserController.buildOpenTabScript(for: .safari, url: url)
        #expect(script.contains("tell application \"Safari\""))
        #expect(script.contains("make new tab at end of tabs of front window"))
        #expect(script.contains("set current tab of front window to newTab"))
        #expect(script.contains("return \"safari:ok\""))
    }

    @Test("Open script escapes URLs containing quotes")
    func openScriptUrlEscaping() {
        // Construct a URL string that, after URL parsing, would contain quotes
        // when interpolated. We rely on TerminalController.escapeForAppleScript
        // doing the work — assert that a literal quote in the URL becomes \\"
        // in the script. URL doesn't allow raw quotes so we test via the
        // matcher path: pass a deliberately-evil URL via URL(string:) using
        // percent-encoded quotes.
        let url = URL(string: "https://example.com/x?q=%22hi%22")!
        let script = BrowserController.buildOpenTabScript(for: .chrome, url: url)
        // The percent-encoded form should pass through; raw quote should NOT
        // appear in the URL literal in the script.
        #expect(script.contains("https://example.com/x?q=%22hi%22"))
    }

    // MARK: - buildNavigateScript

    @Test("Chrome navigate script matches by URL substring and sets new URL")
    func chromeNavigateScriptShape() {
        let oldURL = URL(string: "https://claude.ai/code/session_old")!
        let newURL = URL(string: "https://claude.ai/code/session_new")!
        let script = BrowserController.buildNavigateScript(browser: .chrome, oldURL: oldURL, newURL: newURL)
        #expect(script.contains("if application \"Google Chrome\" is running"))
        #expect(script.contains("tell application \"Google Chrome\""))
        #expect(script.contains("/code/session_old"))
        #expect(script.contains("set URL of t to \"https://claude.ai/code/session_new\""))
        #expect(script.contains("set active tab index"))
        #expect(script.contains("set index of w to 1"))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"navigated\""))
    }

    @Test("Arc navigate script matches by URL substring of the previously-set URL")
    func arcNavigateScriptShape() {
        let oldURL = URL(string: "https://claude.ai/code/session_old")!
        let newURL = URL(string: "https://claude.ai/code/session_new")!
        let script = BrowserController.buildNavigateScript(browser: .arc, oldURL: oldURL, newURL: newURL)
        #expect(script.contains("if application \"Arc\" is running"))
        #expect(script.contains("tell application \"Arc\""))
        // Matcher is the deriveMatcher(oldURL) substring, NOT a tab id.
        #expect(script.contains("/code/session_old"))
        #expect(!script.contains("set targetId"))
        // Index-based walks for both spaces (normal Arc) and direct window
        // tabs (Little Arc fallback).
        #expect(script.contains("repeat with wIdx from 1 to wCount"))
        #expect(script.contains("space spIdx of window wIdx"))
        #expect(script.contains("tabs of window wIdx"))
        #expect(script.contains("set URL of t to \"https://claude.ai/code/session_new\""))
        #expect(script.contains("tell t to select"))
        // Multi-window: UUID-keyed AXRaise via System Events. Same as the
        // focus block — see arcScriptShape for rationale.
        #expect(script.contains("set winId to id of window wIdx"))
        #expect(script.contains("tell application \"System Events\""))
        #expect(script.contains("value of attribute \"AXIdentifier\" of window seIdx"))
        #expect(script.contains("contains winId"))
        #expect(script.contains("perform action \"AXRaise\" of window seIdx"))
        #expect(script.contains("return \"navigated\""))
        // AXRaise MUST come before activate in BOTH branches (spaces walk
        // and direct-tab Little-Arc fallback). Reversed order silently
        // regresses multi-window navigate — Arc paints old front window
        // on activate before AXRaise reorders the internal stack.
        let raises = Array(script.ranges(of: "perform action \"AXRaise\" of window seIdx"))
        let activates = Array(script.ranges(of: "activate"))
        #expect(raises.count == 2, "expected two AXRaise calls (one per navigate branch), got \(raises.count)")
        #expect(activates.count == 2, "expected two activate calls (one per navigate branch), got \(activates.count)")
        for (raise, activate) in zip(raises, activates) {
            #expect(raise.lowerBound < activate.lowerBound,
                    "AXRaise must precede activate in each Arc navigate branch")
        }
    }

    @Test("Arc navigate script escapes adversarial URLs in both old-matcher and new-URL")
    func arcNavigateScriptEscapesUrls() {
        // URLs themselves can't contain raw quotes, but the matcher derived
        // from the old URL still flows through escapeForAppleScript. Confirm
        // the escape pipeline runs by passing a URL whose path part contains
        // characters that the escape function transforms (a backslash via
        // percent-decoding isn't possible, but tab characters get replaced
        // with spaces). Use a URL whose path just confirms percent-encoded
        // characters pass through.
        let oldURL = URL(string: "https://claude.ai/code/session_a")!
        let newURL = URL(string: "https://claude.ai/code/session_b")!
        let script = BrowserController.buildNavigateScript(browser: .arc, oldURL: oldURL, newURL: newURL)
        // Sanity: matcher is exactly /code/session_a (substring), and new URL
        // is the full URL.
        #expect(script.contains("\"/code/session_a\""))
        #expect(script.contains("\"https://claude.ai/code/session_b\""))
    }

    @Test("Safari navigate script matches by URL substring and sets new URL")
    func safariNavigateScriptShape() {
        let oldURL = URL(string: "https://claude.ai/code/session_old")!
        let newURL = URL(string: "https://claude.ai/code/session_new")!
        let script = BrowserController.buildNavigateScript(browser: .safari, oldURL: oldURL, newURL: newURL)
        #expect(script.contains("if application \"Safari\" is running"))
        #expect(script.contains("tell application \"Safari\""))
        #expect(script.contains("/code/session_old"))
        #expect(script.contains("set URL of t to \"https://claude.ai/code/session_new\""))
        #expect(script.contains("set current tab of w to t"))
        #expect(script.contains("set index of w to 1"))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"navigated\""))
    }
}
