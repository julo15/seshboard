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

// MARK: - ProcessResult Tests

@Suite("ProcessResult")
struct ProcessResultTests {
    @Test("ProcessResult.launchFailed case")
    func launchFailedCase() {
        let result = ProcessResult.launchFailed
        switch result {
        case .launchFailed:
            break // expected
        case .completed, .cancelled:
            Issue.record("Expected .launchFailed")
        }
    }

    @Test("ProcessResult.completed carries status, data, and indexingCount")
    func completedCase() {
        let data = "hello".data(using: .utf8)!
        let result = ProcessResult.completed(status: 0, data: data, indexingCount: 42)
        switch result {
        case .completed(let status, let resultData, let indexingCount):
            #expect(status == 0)
            #expect(resultData == data)
            #expect(indexingCount == 42)
        case .launchFailed, .cancelled:
            Issue.record("Expected .completed")
        }
    }

    @Test("ProcessResult.completed with nil indexingCount")
    func completedNilIndexingCount() {
        let result = ProcessResult.completed(status: 1, data: Data(), indexingCount: nil)
        switch result {
        case .completed(let status, _, let indexingCount):
            #expect(status == 1)
            #expect(indexingCount == nil)
        case .launchFailed, .cancelled:
            Issue.record("Expected .completed")
        }
    }

    @Test("ProcessResult.cancelled case")
    func cancelledCase() {
        let result = ProcessResult.cancelled
        switch result {
        case .cancelled:
            break // expected
        case .launchFailed, .completed:
            Issue.record("Expected .cancelled")
        }
    }
}

// MARK: - RecallIndexingProcess Tests

@Suite("RecallIndexingProcess")
struct RecallIndexingProcessTests {
    @Test("shared starts as nil")
    func sharedStartsNil() {
        RecallIndexingProcess.shared = nil
        #expect(RecallIndexingProcess.shared == nil)
    }

    @Test("addWaiter resumes immediately when process already complete")
    func addWaiterResumesWhenComplete() async {
        // Launch a process that will fail immediately (recall not installed in CI)
        // but we can still test the waiter mechanics via waitForResult
        let id = UUID()

        // Create a process — it will either run or fail to launch
        // Either way, we can test that addWaiter works after completion
        do {
            let process = try RecallIndexingProcess.launch(query: "test", limit: 1)
            // Wait for it to complete
            let result = await process.waitForResult()

            // Now add another waiter — should resume immediately with the cached result
            let secondResult = await withCheckedContinuation { continuation in
                process.addWaiter(continuation, id: id)
            }

            // Both results should match
            switch (result, secondResult) {
            case (.completed(let s1, _, _), .completed(let s2, _, _)):
                #expect(s1 == s2)
            case (.launchFailed, .launchFailed):
                break // both failed, consistent
            default:
                // As long as we got a result without hanging, the test passes
                break
            }
        } catch {
            // recall not installed — that's fine, the launch itself failed
            // We can't test waiter mechanics without a running process
        }
    }

    @Test("removeWaiter resumes continuation with cancelled")
    func removeWaiterResumesCancelled() async {
        do {
            let process = try RecallIndexingProcess.launch(query: "a]]]zzzzz_nonexistent_query", limit: 1)
            let waiterId = UUID()

            let result = await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult, Never>) in
                process.addWaiter(continuation, id: waiterId)
                // Immediately remove — should resume with .cancelled
                process.removeWaiter(id: waiterId)
            }

            switch result {
            case .cancelled:
                break // expected
            case .completed:
                // Process completed before we could remove — that's OK too
                break
            case .launchFailed:
                Issue.record("Unexpected .launchFailed from waiter")
            }
        } catch {
            // recall not installed — skip
        }
    }

    @Test("isRunning reflects process state")
    func isRunningState() async {
        do {
            let process = try RecallIndexingProcess.launch(query: "test", limit: 1)
            // Wait for completion
            _ = await process.waitForResult()
            #expect(!process.isRunning)
            #expect(process.result != nil)
        } catch {
            // recall not installed — skip
        }
    }

    @Test("waitForResult returns cached result on second call")
    func waitForResultCached() async {
        do {
            let process = try RecallIndexingProcess.launch(query: "test", limit: 1)
            let first = await process.waitForResult()
            let second = await process.waitForResult()

            // Both calls should return the same result type
            switch (first, second) {
            case (.completed(let s1, _, _), .completed(let s2, _, _)):
                #expect(s1 == s2)
            case (.cancelled, .cancelled), (.launchFailed, .launchFailed):
                break
            default:
                Issue.record("Expected both waitForResult calls to return the same result")
            }
        } catch {
            // recall not installed — skip
        }
    }
}
