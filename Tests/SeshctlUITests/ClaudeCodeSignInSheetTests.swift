import Foundation
import Testing

@testable import SeshctlUI

/// Builds an HTTPCookie scoped to `.claude.ai` (or the provided domain) for
/// the success-detection helper's filter logic.
private func makeCookie(
    name: String,
    value: String = "v",
    domain: String = ".claude.ai"
) -> HTTPCookie {
    // swiftlint:disable:next force_unwrapping — inputs are constant, always valid
    HTTPCookie(properties: [
        .domain: domain,
        .path: "/",
        .name: name,
        .value: value,
        .secure: "TRUE",
    ])!
}

@Suite("ClaudeCodeSignInSheet.shouldConsiderSignedIn")
struct ClaudeCodeSignInSheetTests {
    @Test("sign-in detected by /code URL alone")
    func signInByCodeURLAlone() {
        let url = URL(string: "https://claude.ai/code")
        #expect(ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: []))
    }

    @Test("sign-in detected by /code/session/... URL")
    func signInByCodeSessionURL() {
        let url = URL(string: "https://claude.ai/code/session/cse_abc")
        #expect(ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: []))
    }

    @Test("sign-in detected by both cookies alone")
    func signInByBothCookies() {
        let url = URL(string: "https://claude.ai/login")
        let cookies = [
            makeCookie(name: "sessionKey"),
            makeCookie(name: "sessionKeyLC"),
        ]
        #expect(ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: cookies))
    }

    @Test("only sessionKey present is not enough")
    func onlySessionKey() {
        let url = URL(string: "https://claude.ai/login")
        let cookies = [makeCookie(name: "sessionKey")]
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: cookies))
    }

    @Test("only sessionKeyLC present is not enough")
    func onlySessionKeyLC() {
        let url = URL(string: "https://claude.ai/login")
        let cookies = [makeCookie(name: "sessionKeyLC")]
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: cookies))
    }

    @Test("nil url and no cookies means not signed in")
    func nilURLNoCookies() {
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: nil, cookies: []))
    }

    @Test("wrong host ignored")
    func wrongHost() {
        let url = URL(string: "https://otherdomain.com/code")
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: []))
    }

    @Test("wrong path ignored")
    func wrongPath() {
        let url = URL(string: "https://claude.ai/login")
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: []))
    }

    @Test("cookies on different domain ignored")
    func cookiesOnDifferentDomain() {
        let url = URL(string: "https://claude.ai/login")
        let cookies = [
            makeCookie(name: "sessionKey", domain: ".example.com"),
            makeCookie(name: "sessionKeyLC", domain: ".example.com"),
        ]
        #expect(!ClaudeCodeSignInSheet.shouldConsiderSignedIn(url: url, cookies: cookies))
    }
}
