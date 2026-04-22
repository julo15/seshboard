import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

@Suite("SignInBanner.presentation")
struct SignInBannerPresentationTests {

    @Test("notConnected maps to .connect")
    func notConnectedIsConnect() {
        let presentation = SignInBanner.presentation(for: .notConnected)
        #expect(presentation == .connect)
    }

    @Test("connecting maps to .connecting")
    func connectingIsConnecting() {
        let presentation = SignInBanner.presentation(for: .connecting)
        #expect(presentation == .connecting)
    }

    @Test("connected with no fetch date maps to .hidden")
    func connectedNoDateHidden() {
        let presentation = SignInBanner.presentation(for: .connected(lastFetchAt: nil))
        #expect(presentation == .hidden)
    }

    @Test("connected with fetch date maps to .hidden")
    func connectedWithDateHidden() {
        let presentation = SignInBanner.presentation(for: .connected(lastFetchAt: Date()))
        #expect(presentation == .hidden)
    }

    @Test("authExpired maps to .reconnect")
    func authExpiredIsReconnect() {
        let presentation = SignInBanner.presentation(for: .authExpired)
        #expect(presentation == .reconnect)
    }

    @Test("transientError maps to .hidden (inline on rows, no global banner)")
    func transientErrorHidden() {
        let presentation = SignInBanner.presentation(for: .transientError("HTTP 503"))
        #expect(presentation == .hidden)
    }
}
