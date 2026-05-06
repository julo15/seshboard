import Foundation
import Testing
@testable import SeshctlCore

@Suite("ManagedTab")
struct ManagedTabTests {
    @Test("ManagedTab equality compares all fields")
    func managedTabEquality() {
        let url = URL(string: "https://claude.ai/code/session_x")!
        let a = ManagedTab(browser: .chrome, identifier: .chrome(tabId: 1), url: url)
        let b = ManagedTab(browser: .chrome, identifier: .chrome(tabId: 1), url: url)
        let c = ManagedTab(browser: .chrome, identifier: .chrome(tabId: 2), url: url)
        let d = ManagedTab(browser: .arc, identifier: .arc(tabId: "tab-1"), url: url)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("TabIdentifier cases are not equal across browsers")
    func tabIdentifierCrossBrowserInequality() {
        let url = URL(string: "https://claude.ai/code/session_x")!
        let chrome: TabIdentifier = .chrome(tabId: 7)
        let arc: TabIdentifier = .arc(tabId: "7")
        let safari: TabIdentifier = .safari(windowId: 7, url: url)
        #expect(chrome != arc)
        #expect(chrome != safari)
        #expect(arc != safari)
    }

    @Test("TabIdentifier safari case compares windowId and URL together")
    func safariIdentifierEquality() {
        let url1 = URL(string: "https://claude.ai/code/session_a")!
        let url2 = URL(string: "https://claude.ai/code/session_b")!
        #expect(TabIdentifier.safari(windowId: 1, url: url1) == .safari(windowId: 1, url: url1))
        #expect(TabIdentifier.safari(windowId: 1, url: url1) != .safari(windowId: 2, url: url1))
        #expect(TabIdentifier.safari(windowId: 1, url: url1) != .safari(windowId: 1, url: url2))
    }
}
