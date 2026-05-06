import Foundation
import Testing
@testable import SeshctlCore

@Suite("ManagedTab")
struct ManagedTabTests {
    @Test("ManagedTab equality compares browser and url")
    func managedTabEquality() {
        let urlA = URL(string: "https://claude.ai/code/session_a")!
        let urlB = URL(string: "https://claude.ai/code/session_b")!
        let chromeA = ManagedTab(browser: .chrome, url: urlA)
        let chromeASame = ManagedTab(browser: .chrome, url: urlA)
        let chromeB = ManagedTab(browser: .chrome, url: urlB)
        let arcA = ManagedTab(browser: .arc, url: urlA)
        #expect(chromeA == chromeASame)
        #expect(chromeA != chromeB)
        #expect(chromeA != arcA)
    }
}
