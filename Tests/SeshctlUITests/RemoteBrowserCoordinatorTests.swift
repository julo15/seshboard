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
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("chrome:42", fallbackURL: url)
        #expect(parsed == ManagedTab(browser: .chrome, identifier: .chrome(tabId: 42), url: url))
    }

    @Test("parseOpenTabOutput parses Arc stdout")
    func parseArcOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("arc:tab-uuid-abc", fallbackURL: url)
        #expect(parsed == ManagedTab(browser: .arc, identifier: .arc(tabId: "tab-uuid-abc"), url: url))
    }

    @Test("parseOpenTabOutput parses Safari stdout including the URL after the pipe")
    func parseSafariOutput() {
        let fallback = URL(string: "https://claude.ai/code/session_fallback")!
        let parsed = RemoteBrowserCoordinator.parseOpenTabOutput("safari:7|https://claude.ai/code/session_a", fallbackURL: fallback)
        let expectedUrl = URL(string: "https://claude.ai/code/session_a")!
        // For Safari, the URL inside the payload becomes BOTH the identifier's
        // url field AND the ManagedTab.url field (since the AppleScript captures
        // exactly what we set on the tab).
        #expect(parsed == ManagedTab(browser: .safari, identifier: .safari(windowId: 7, url: expectedUrl), url: expectedUrl))
    }

    @Test("parseOpenTabOutput rejects malformed input")
    func parseMalformedOutput() {
        let url = URL(string: "https://claude.ai/code/session_a")!
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("nope", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("chrome:not-an-int", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("arc:", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("safari:7", fallbackURL: url) == nil) // missing pipe
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("safari:notanint|https://x", fallbackURL: url) == nil)
        #expect(RemoteBrowserCoordinator.parseOpenTabOutput("brave:42", fallbackURL: url) == nil)
    }

    // MARK: - First click (open + track)

    @Test("First click with supported default opens a new tab via AppleScript and tracks it")
    func firstClickOpensAndTracks() {
        let env = MockSystemEnvironment()
        env.runningApps = []  // nothing to focus
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") && script.contains("Google Chrome") {
                return "chrome:42"
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
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, identifier: .chrome(tabId: 42), url: url))
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

    @Test("Second click navigates the tracked tab by id and updates tracked URL")
    func secondClickNavigatesByIdAndUpdatesTracking() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            // Focus combined script for the new URL — no match.
            if script.contains("if URL of tab") || script.contains("/code/session_b") && !script.contains("set URL") {
                return ""
            }
            // Navigate-by-id script for the tracked Chrome tab — succeed.
            if script.contains("set targetId to 42") && script.contains("set URL of t to") {
                return "navigated"
            }
            return ""
        }

        let coord = RemoteBrowserCoordinator()
        // Seed a tracked managed tab via a synthetic first click.
        let urlA = URL(string: "https://claude.ai/code/session_a")!
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") { return "chrome:42" }
            return ""
        }
        coord.openOrFocus(url: urlA, environment: env, defaultBrowser: .chrome)
        env.executedScripts.removeAll()
        env.openedURLs.removeAll()

        // Re-set provider for the second click.
        env.appleScriptOutputProvider = { script in
            // Combined focus script: contains the focus blocks (we recognize via "if URL of tab").
            if script.contains("if URL of tab") {
                return "" // nothing matches the new URL
            }
            // Navigate-by-id script: targets our tracked tab id.
            if script.contains("set targetId to 42") {
                return "navigated"
            }
            return ""
        }

        let urlB = URL(string: "https://claude.ai/code/session_b")!
        coord.openOrFocus(url: urlB, environment: env, defaultBrowser: .chrome)

        // No fallback.
        #expect(env.openedURLs.isEmpty)
        // Two scripts on the second click: focus + navigate.
        #expect(env.executedScripts.count == 2)
        #expect(env.executedScripts[0].contains("if URL of tab"))         // combined focus
        #expect(env.executedScripts[1].contains("set targetId to 42"))    // navigate-by-id
        // Tracking updated to new URL but same identifier.
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, identifier: .chrome(tabId: 42), url: urlB))
    }

    // MARK: - Existing tab found by URL → step 1 short-circuits

    @Test("Existing tab matching new URL is focused; tracking unchanged")
    func existingTabFocusedNoTrackingChange() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            if script.contains("if URL of tab") { return "found" }
            return ""
        }

        let coord = RemoteBrowserCoordinator()
        let url = URL(string: "https://claude.ai/code/session_x")!
        coord.openOrFocus(url: url, environment: env, defaultBrowser: .chrome)

        // Exactly one script — the focus script. No open/navigate.
        #expect(env.executedScripts.count == 1)
        #expect(env.executedScripts[0].contains("if URL of tab"))
        #expect(env.openedURLs.isEmpty)
        // No tracking change (still nil).
        #expect(coord.trackedManagedTabForTesting == nil)
    }

    // MARK: - Managed tab gone → fall through to open

    @Test("Managed tab gone (navigate miss) clears tracking and falls through to open")
    func managedTabGoneFallsThroughToOpen() {
        let env = MockSystemEnvironment()
        env.runningApps = ["com.google.Chrome"]
        env.appleScriptOutputProvider = { script in
            // Focus: nothing matches.
            if script.contains("if URL of tab") { return "" }
            // Navigate-by-id: tab not found.
            if script.contains("set targetId to 99") { return "" }
            // Open: succeeds.
            if script.contains("make new tab") { return "chrome:7" }
            return ""
        }

        let coord = RemoteBrowserCoordinator()
        // Seed tracking with a stale tab.
        let staleUrl = URL(string: "https://claude.ai/code/session_stale")!
        env.appleScriptOutputProvider = { script in
            if script.contains("make new tab") { return "chrome:99" }
            return ""
        }
        coord.openOrFocus(url: staleUrl, environment: env, defaultBrowser: .chrome)
        #expect(coord.trackedManagedTabForTesting?.identifier == .chrome(tabId: 99))
        env.executedScripts.removeAll()

        // Reset provider for the next click.
        env.appleScriptOutputProvider = { script in
            if script.contains("if URL of tab") { return "" }
            if script.contains("set targetId to 99") { return "" } // navigate misses
            if script.contains("make new tab") { return "chrome:7" }
            return ""
        }

        let newUrl = URL(string: "https://claude.ai/code/session_new")!
        coord.openOrFocus(url: newUrl, environment: env, defaultBrowser: .chrome)

        // Three scripts: focus + navigate (miss) + open.
        #expect(env.executedScripts.count == 3)
        #expect(env.executedScripts[0].contains("if URL of tab"))
        #expect(env.executedScripts[1].contains("set targetId to 99"))
        #expect(env.executedScripts[2].contains("make new tab"))
        // Tracking refreshed to new tab id.
        #expect(coord.trackedManagedTabForTesting == ManagedTab(browser: .chrome, identifier: .chrome(tabId: 7), url: newUrl))
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
