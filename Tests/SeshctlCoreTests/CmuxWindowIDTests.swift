import Foundation
import Testing

@testable import SeshctlCore

@Suite("CmuxWindowID - parse")
struct CmuxWindowIDTests {

    @Test("Returns nil for nil windowId")
    func nilWindowId() {
        #expect(CmuxWindowID.parse(nil) == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        #expect(CmuxWindowID.parse("") == nil)
    }

    @Test("Returns workspace-only when no separator (legacy session)")
    func noSeparator() {
        let result = CmuxWindowID.parse("AAAAAAAA-0000-0000-0000-000000000001")
        #expect(result?.workspaceId == "AAAAAAAA-0000-0000-0000-000000000001")
        #expect(result?.surfaceId == nil)
    }

    @Test("Returns workspace-only when separator with empty surface")
    func emptyAfterSeparator() {
        let result = CmuxWindowID.parse("AAAAAAAA-0000-0000-0000-000000000001|")
        #expect(result?.workspaceId == "AAAAAAAA-0000-0000-0000-000000000001")
        #expect(result?.surfaceId == nil)
    }

    @Test("Returns workspace-only when separator with whitespace-only surface")
    func whitespaceAfterSeparator() {
        let result = CmuxWindowID.parse("AAAAAAAA-0000-0000-0000-000000000001|   ")
        #expect(result?.workspaceId == "AAAAAAAA-0000-0000-0000-000000000001")
        #expect(result?.surfaceId == nil)
    }

    @Test("Parses both UUIDs from valid packed form")
    func validPacked() {
        let workspace = "AAAAAAAA-0000-0000-0000-000000000001"
        let surface = "CCCCCCCC-0000-0000-0000-000000000001"
        let result = CmuxWindowID.parse("\(workspace)|\(surface)")
        #expect(result?.workspaceId == workspace)
        #expect(result?.surfaceId == surface)
    }

    @Test("Trims whitespace around surface UUID")
    func trimsSurfaceWhitespace() {
        let workspace = "AAAAAAAA-0000-0000-0000-000000000001"
        let surface = "CCCCCCCC-0000-0000-0000-000000000001"
        let result = CmuxWindowID.parse("\(workspace)|  \(surface)  ")
        #expect(result?.surfaceId == surface)
    }
}
