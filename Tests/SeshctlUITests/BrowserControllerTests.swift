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

    @Test("Arc script walks spaces of windows and uses select")
    func arcScriptShape() {
        let script = BrowserController.buildFocusScript(for: .arc, matcher: "/code/session_X")
        #expect(script.contains("if application \"Arc\" is running"))
        #expect(script.contains("tell application \"Arc\""))
        #expect(script.contains("spaces of w"))
        #expect(script.contains("tell t to select"))
        #expect(script.contains("activate"))
        #expect(script.contains("return \"found\""))
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

    // MARK: - tryFocusInBrowser

    @Test("tryFocusInBrowser returns true when AppleScript prints \"found\"")
    func tryFocusReturnsTrueOnFound() {
        let env = MockSystemEnvironment()
        env.appleScriptOutputs = ["found"]
        #expect(BrowserController.tryFocusInBrowser(.chrome, matcher: "/code/session_X", env: env))
    }

    @Test("tryFocusInBrowser returns false on empty stdout")
    func tryFocusReturnsFalseOnEmpty() {
        let env = MockSystemEnvironment()
        env.appleScriptOutputs = [""]
        #expect(!BrowserController.tryFocusInBrowser(.chrome, matcher: "/code/session_X", env: env))
    }

    @Test("tryFocusInBrowser returns false when AppleScript fails (nil stdout)")
    func tryFocusReturnsFalseOnNil() {
        let env = MockSystemEnvironment()
        env.appleScriptOutputs = [nil]
        #expect(!BrowserController.tryFocusInBrowser(.chrome, matcher: "/code/session_X", env: env))
    }

    // MARK: - focusOrOpen end-to-end

    @Test("focusOrOpen falls back to env.openURL when no browsers are running")
    func focusOrOpenNoBrowsersFallsBack() {
        let env = MockSystemEnvironment()
        env.runningApps = [] // no browsers running

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env)

        #expect(env.openedURLs == [url])
        #expect(env.executedScripts.isEmpty)
    }

    @Test("focusOrOpen probes default-running browser and skips fallback on hit")
    func focusOrOpenProbesAndSkipsFallback() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            script.contains("Google Chrome") ? "found" : ""
        }

        // Override the LaunchServices-backed default lookup so the test does
        // not depend on the host's default browser configuration.
        let original = BrowserController.defaultBrowserResolver
        BrowserController.defaultBrowserResolver = { .chrome }
        defer { BrowserController.defaultBrowserResolver = original }

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env)

        #expect(env.openedURLs.isEmpty)
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("Google Chrome"))
    }

    @Test("focusOrOpen tries each running browser and falls back when none match")
    func focusOrOpenTriesAllAndFallsBack() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"]
        env.appleScriptOutputProvider = { _ in "" }

        let original = BrowserController.defaultBrowserResolver
        BrowserController.defaultBrowserResolver = { nil }
        defer { BrowserController.defaultBrowserResolver = original }

        let url = URL(string: "https://claude.ai/code/session_abc")!
        BrowserController.focusOrOpen(url: url, environment: env)

        #expect(env.executedScripts.count == 3)
        #expect(env.openedURLs == [url])
    }

    // MARK: - probeOrder

    @Test("probeOrder skips non-running browsers")
    func probeOrderSkipsNonRunning() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]

        let original = BrowserController.defaultBrowserResolver
        BrowserController.defaultBrowserResolver = { nil }
        defer { BrowserController.defaultBrowserResolver = original }

        #expect(BrowserController.probeOrder(env: env) == [.chrome])
    }

    @Test("probeOrder puts default browser first when running")
    func probeOrderDefaultBrowserFirst() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari"]

        let original = BrowserController.defaultBrowserResolver
        BrowserController.defaultBrowserResolver = { .safari }
        defer { BrowserController.defaultBrowserResolver = original }

        let order = BrowserController.probeOrder(env: env)
        #expect(order.first == .safari)
        #expect(Set(order) == Set([BrowserApp.chrome, .arc, .safari]))
    }

    @Test("probeOrder ignores default browser when it isn't running")
    func probeOrderIgnoresNonRunningDefault() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]

        let original = BrowserController.defaultBrowserResolver
        BrowserController.defaultBrowserResolver = { .arc }
        defer { BrowserController.defaultBrowserResolver = original }

        #expect(BrowserController.probeOrder(env: env) == [.chrome])
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
}
