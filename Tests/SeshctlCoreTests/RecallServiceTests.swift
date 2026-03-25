import Foundation
import Testing

@testable import SeshctlCore

@Suite("RecallService")
struct RecallServiceTests {
    @Test("isAvailable returns without crashing")
    func isAvailableReturnsBool() {
        let result = RecallService.isAvailable()
        // Just verify it returns a Bool without crashing
        #expect(result == true || result == false)
    }

    @Test("Search with empty query returns empty results")
    func searchEmptyQuery() async throws {
        let results = try await RecallService.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Search with whitespace query returns empty results")
    func searchWhitespaceQuery() async throws {
        let results = try await RecallService.search(query: "   ")
        #expect(results.isEmpty)
    }
}
