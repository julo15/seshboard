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
        let response = try await RecallService.search(query: "")
        #expect(response.results.isEmpty)
        #expect(response.indexingCount == nil)
    }

    @Test("Search with whitespace query returns empty results")
    func searchWhitespaceQuery() async throws {
        let response = try await RecallService.search(query: "   ")
        #expect(response.results.isEmpty)
        #expect(response.indexingCount == nil)
    }

    @Test("parseIndexingCount returns count from valid indexing status")
    func parseIndexingCountValid() {
        let stderr = "{\"status\": \"indexing\", \"count\": 42}\n".data(using: .utf8)!
        #expect(RecallService.parseIndexingCount(from: stderr) == 42)
    }

    @Test("parseIndexingCount returns nil for empty data")
    func parseIndexingCountEmpty() {
        #expect(RecallService.parseIndexingCount(from: Data()) == nil)
    }

    @Test("parseIndexingCount returns nil when status is not indexing")
    func parseIndexingCountWrongStatus() {
        let stderr = "{\"status\": \"ready\", \"count\": 10}\n".data(using: .utf8)!
        #expect(RecallService.parseIndexingCount(from: stderr) == nil)
    }

    @Test("parseIndexingCount returns nil when count is missing")
    func parseIndexingCountNoCount() {
        let stderr = "{\"status\": \"indexing\"}\n".data(using: .utf8)!
        #expect(RecallService.parseIndexingCount(from: stderr) == nil)
    }

    @Test("parseIndexingCount ignores non-JSON lines")
    func parseIndexingCountMixedLines() {
        let stderr = "some log line\n{\"status\": \"indexing\", \"count\": 7}\nanother line\n".data(using: .utf8)!
        #expect(RecallService.parseIndexingCount(from: stderr) == 7)
    }

    @Test("parseIndexingCount returns first matching line")
    func parseIndexingCountFirstMatch() {
        let stderr = "{\"status\": \"indexing\", \"count\": 3}\n{\"status\": \"indexing\", \"count\": 5}\n".data(using: .utf8)!
        #expect(RecallService.parseIndexingCount(from: stderr) == 3)
    }
}
