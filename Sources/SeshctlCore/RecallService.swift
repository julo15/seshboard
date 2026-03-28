import Foundation

public enum RecallError: Error {
    case notInstalled
    case timeout
    case searchFailed(String)
}

public struct RecallSearchResponse: Sendable {
    public let results: [RecallResult]
    public let indexingCount: Int?
}

public struct RecallService: Sendable {

    public static func search(
        query: String,
        limit: Int = 10,
        onIndexing: (@Sendable (Int) -> Void)? = nil
    ) async throws -> RecallSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return RecallSearchResponse(results: [], indexingCount: nil) }

        let searchTask = Task.detached { @Sendable () -> RecallSearchResponse in
            try await runRecallProcess(query: trimmed, limit: limit, onIndexing: onIndexing)
        }

        let timeoutTask = Task.detached { @Sendable () -> RecallSearchResponse in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            searchTask.cancel()
            throw RecallError.timeout
        }

        do {
            let response = try await searchTask.value
            timeoutTask.cancel()
            return response
        } catch is CancellationError {
            throw RecallError.timeout
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    public static func isAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "recall"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0
    }

    // MARK: - Private

    @Sendable
    private static func runRecallProcess(
        query: String,
        limit: Int,
        onIndexing: (@Sendable (Int) -> Void)?
    ) async throws -> RecallSearchResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["recall", "--json", "-n", "\(limit)", query]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream stderr to detect indexing status while the process runs
        let stderrBuffer = StderrBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let count = stderrBuffer.append(data) {
                onIndexing?(count)
            }
        }

        let result: ProcessResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: .launchFailed)
                    return
                }

                process.terminationHandler = { terminatedProcess in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let indexingCount = stderrBuffer.indexingCount
                    continuation.resume(returning: .completed(
                        status: terminatedProcess.terminationStatus,
                        data: data,
                        indexingCount: indexingCount
                    ))
                }
            }
        } onCancel: {
            process.terminate()
        }

        try Task.checkCancellation()

        switch result {
        case .launchFailed:
            throw RecallError.notInstalled
        case let .completed(status, data, indexingCount):
            guard status == 0 else {
                let output = String(data: data, encoding: .utf8) ?? ""
                throw RecallError.searchFailed(
                    "recall exited with status \(status): \(output)"
                )
            }

            do {
                let results = try JSONDecoder().decode([RecallResult].self, from: data)
                return RecallSearchResponse(results: results, indexingCount: indexingCount)
            } catch {
                throw RecallError.searchFailed(
                    "Failed to decode recall output: \(error.localizedDescription)"
                )
            }
        }
    }

    static func parseIndexingCount(from stderrData: Data) -> Int? {
        guard let stderrString = String(data: stderrData, encoding: .utf8) else { return nil }
        for line in stderrString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{") else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["status"] as? String == "indexing",
                  let count = json["count"] as? Int else { continue }
            return count
        }
        return nil
    }
}

private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var _indexingCount: Int?

    var indexingCount: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _indexingCount
    }

    /// Appends data, scans for complete lines, returns indexing count if found.
    func append(_ data: Data) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard _indexingCount == nil else { return nil }  // Already found
        buffer.append(data)

        // Scan for complete lines
        guard let str = String(data: buffer, encoding: .utf8) else { return nil }
        for line in str.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["status"] as? String == "indexing",
                  let count = json["count"] as? Int else { continue }
            _indexingCount = count
            return count
        }
        return nil
    }
}

private enum ProcessResult: Sendable {
    case launchFailed
    case completed(status: Int32, data: Data, indexingCount: Int?)
}
