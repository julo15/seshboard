import Foundation
import Testing
@testable import SeshctlCore
@testable import SeshctlUI

@Suite("RemoteBrowserCoordinator")
struct RemoteBrowserCoordinatorTests {

    // MARK: - parseOpenTabOutput

    @Test("parseOpenTabOutput parses Chrome stdout")
    func parseChromeOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("chrome:ok", fallbackURL: url)
        #expect(parsed == ManagedTab(browser: .chrome, url: url))
    }

    @Test("parseOpenTabOutput parses Arc stdout")
    func parseArcOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("arc:ok", fallbackURL: url)
        #expect(parsed == ManagedTab(browser: .arc, url: url))
    }

    @Test("parseOpenTabOutput parses Safari stdout")
    func parseSafariOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("safari:ok", fallbackURL: url)
        #expect(parsed == ManagedTab(browser: .safari, url: url))
    }

    @Test("parseOpenTabOutput rejects malformed input")
    func parseMalformedOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("nope", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("chrome:42", fallbackURL: url) == nil)        // payload must be "ok"
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("arc:", fallbackURL: url) == nil)            // empty payload
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("safari:7|https://x", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("brave:ok", fallbackURL: url) == nil)
    }

    // MARK: - First click (open + track)

    @Test("First click with supported default opens a new tab via AppleScript and tracks it")
    func firstClickOpensAndTracks() {
        let env = MockSystemEnvironment()
        env.runningApps = []  // nothing to focus
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") && script.contains("Google Chrome") {
                return "chrome:ok"
            }
            return ""
        }

        let coord = RemoteBrowserCoordinator()
        let url = URL(string: "https://claude.ai/code/session_a")!
        coord.openOrFocus(url: url, environment: env, defaultBrowser: .chrome)

        // No fallback to NSWorkspace.
        #expect(env.openedURLs.isEmpty)
        // Exactly one script ran (the open script — no probe order, no managed tab).
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("make new tab"))
        // Tracking captured.
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, url: url))
    }

    @Test("First click falls through to NSWorkspace when default browser is unsupported")
    func firstClickFallsThroughWhenUnsupported() {
        let env = MockSystemEnvironment()
        env.runningApps = []

        let coord = RemoteBrowserCoordinator()
        let url = URL(string: "https://claude.ai/code/session_a")!
        coord.openOrFocus(url: url, environment: env, defaultBrowser: nil)

        // No AppleScript ran.
        #expect(env.executedScripts.isEmpty)
        // Fallback used.
        #expect(env.openedURLs == [url])
        // No tracking.
        #expect(coord.trackedManagedTabForTesting == nil)
    }

    // MARK: - Second click (navigate + update tracking)

    @Test("Second click navigates the tracked tab by URL match and updates tracked URL")
    func secondClickNavigatesByIdAndUpdatesTracking() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]

        let coord = RemoteBrowserCoordinator()
        // Seed a tracked managed tab via a synthetic first click.
        let urlA = URL(string: "https://claude.ai/code/session_a")!
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") { return "chrome:ok" }
            return ""
        }
        coord.openOrFocus(url: urlA, environment: env, defaultBrowser: .chrome)
        env.executedScripts.removeAll()
        env.openedURLs.removeAll()

        // Re-set provider for the second click.
        env.appleScriptOutputProvider = { script in
            // Combined focus script: contains the focus blocks (we recognize via "every tab of").
            if script.contains("every tab of") && !script.contains("set URL of") {
                return "" // nothing matches the new URL
            }
            // Navigate script: matches by old URL substring.
            if script.contains("/code/session_a") && script.contains("set URL of") {
                return "navigated"
            }
            return ""
        }

        let urlB = URL(string: "https://claude.ai/code/session_b")!
        coord.openOrFocus(url: urlB, environment: env, defaultBrowser: .chrome)

        // No fallback.
        #expect(env.openedURLs.isEmpty)
        // Single script on the second click: navigate-only (we skip the focus
        // probe in the fast path because we have a tracked managed tab).
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("/code/session_a"))    // old matcher (the tracked URL)
        #expect(env.executedScripts[0].contains("set URL of targetTab"))   // navigate, not focus
        // Tracking updated to new URL but same browser.
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, url: urlB))
    }

    // MARK: - Existing tab found by URL → step 1 short-circuits

    @Test("Existing tab matching new URL is focused; tracking unchanged")
    func existingTabFocusedNoTrackingChange() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            if script.contains("every tab of") && !script.contains("set URL of") { return "found" }
            return ""
        }

        let coord = RemoteBrowserCoordinator()
        let url = URL(string: "https://claude.ai/code/session_x")!
        coord.openOrFocus(url: url, environment: env, defaultBrowser: .chrome)

        // Exactly one script — the focus script. No open/navigate.
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("every tab of"))    // combined focus probe with whose filter
        #expect(env.openedURLs.isEmpty)
        // No tracking change (still nil).
        #expect(coord.trackedManagedTabForTesting == nil)
    }

    // MARK: - Managed tab gone → fall through to open

    @Test("Managed tab gone (navigate miss) clears tracking and falls through to open")
    func managedTabGoneFallsThroughToOpen() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]

        let coord = RemoteBrowserCoordinator()
        // Seed tracking with a stale tab.
        let staleUrl = URL(string: "https://claude.ai/code/session_stale")!
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") { return "chrome:ok" }
            return ""
        }
        coord.openOrFocus(url: staleUrl, environment: env, defaultBrowser: .chrome)
        #expect(coord.trackedManagedTabForTesting?.url == staleUrl)
        env.executedScripts.removeAll()

        // Reset provider for the next click.
        env.appleScriptOutputProvider = { script in
            if script.contains("every tab of") && !script.contains("set URL of") { return "" }
            // Navigate script: looks for the stale URL substring — miss.
            if script.contains("/code/session_stale") && script.contains("set URL of") { return "" }
            if script.contains("make new tab") { return "chrome:ok" }
            return ""
        }

        let newUrl = URL(string: "https://claude.ai/code/session_new")!
        coord.openOrFocus(url: newUrl, environment: env, defaultBrowser: .chrome)

        // Three scripts in new order: navigate (miss), focus (miss), open.
        #expect(env.executedScripts.count == 3)
        #expect(env.executedScripts[0].contains("set URL of targetTab"))   // navigate first
        #expect(env.executedScripts[1].contains("every tab of"))           // then combined focus probe with whose filter
        #expect(env.executedScripts[2].contains("make new tab"))           // finally open
        // Tracking refreshed to new URL.
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, url: newUrl))
        // No NSWorkspace fallback.
        #expect(env.openedURLs.isEmpty)
    }

    // MARK: - Open script fails → ultimate NSWorkspace fallback

    @Test("If open script fails to parse, coordinator still falls back to env.openURL")
    func openScriptFailureFallsBackToNSWorkspace() {
        let env = MockSystemEnvironment()
        env.runningApps = []
        env.appleScriptOutputProvider = { _ in nil } // every script returns nil (osascript "failure")

        let coord = RemoteBrowserCoordinator()
        let url = URL(string: "https://claude.ai/code/session_x")!
        coord.openOrFocus(url: url, environment: env, defaultBrowser: .chrome)

        // Open script attempted (one call), then NSWorkspace fallback.
        #expect(env.executedScripts.count == 1)
        #expect(env.openedURLs == [url])
        #expect(coord.trackedManagedTabForTesting == nil)
    }
}
