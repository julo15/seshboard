import Foundation
import Testing
@testable import SeshctlCore

@Suite("RealProcessInfoProvider")
struct ProcessInfoProviderTests {
    @Test("Returns non-zero parent pid for current process")
    func parentPidOfSelf() {
        let p = RealProcessInfoProvider()
        let pid = Int(getpid())
        let parent = p.parentPid(of: pid)
        #expect(parent > 1)
    }

    @Test("Returns non-nil start time for current process")
    func startTimeOfSelf() {
        let p = RealProcessInfoProvider()
        let pid = Int(getpid())
        let start = p.startTime(of: pid)
        #expect(start != nil)
        if let start {
            let now = Int(Date().timeIntervalSince1970)
            #expect(start <= now)
            #expect(now - start < 3600)
        }
    }

    @Test("Returns 0 / nil for non-existent pid")
    func invalidPid() {
        let p = RealProcessInfoProvider()
        #expect(p.parentPid(of: 999_999_999) == 0)
        #expect(p.startTime(of: 999_999_999) == nil)
    }
}
