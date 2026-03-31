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
        onIndexing: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> RecallSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return RecallSearchResponse(results: [], indexingCount: nil) }

        let searchTask = Task.detached { @Sendable () -> RecallSearchResponse in
            try await runRecallProcess(query: trimmed, limit: limit, onIndexing: onIndexing)
        }

        let timeoutTask = Task.detached { @Sendable () -> RecallSearchResponse in
            try await Task.sleep(nanoseconds: 30_000_000_000)
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
        onIndexing: (@Sendable (Int, Int) -> Void)?
    ) async throws -> RecallSearchResponse {
        // Check for in-flight process — reuse it to avoid killing indexing
        let indexingProcess: RecallIndexingProcess
        let reused: Bool
        if let existing = RecallIndexingProcess.shared, existing.isRunning {
            indexingProcess = existing
            reused = true
        } else {
            indexingProcess = try RecallIndexingProcess.launch(query: query, limit: limit)
            RecallIndexingProcess.shared = indexingProcess
            reused = false
        }

        // Emit current progress immediately (stream only yields future updates)
        if let done = indexingProcess.latestDone, let total = indexingProcess.latestTotal {
            onIndexing?(done, total)
        }

        // Subscribe to future progress updates
        let progressId = UUID()
        if let onIndexing {
            indexingProcess.subscribeToProgress(id: progressId) { done, total in
                onIndexing(done, total)
            }
        }

        // Wait for completion (cancellation-aware via waiter removal)
        let waiterId = UUID()
        let result: ProcessResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                indexingProcess.addWaiter(continuation, id: waiterId)
            }
        } onCancel: {
            indexingProcess.removeWaiter(id: waiterId)
        }
        indexingProcess.unsubscribeFromProgress(id: progressId)

        try Task.checkCancellation()

        switch result {
        case .launchFailed:
            throw RecallError.notInstalled
        case .cancelled:
            throw CancellationError()
        case let .completed(status, data, indexingCount):
            guard status == 0 else {
                let output = String(data: data, encoding: .utf8) ?? ""
                throw RecallError.searchFailed(
                    "recall exited with status \(status): \(output)"
                )
            }

            if reused {
                // Results are for the original query. Run a quick follow-up search
                // now that indexing is complete (will be fast).
                return try await runFollowUpSearch(
                    query: query,
                    limit: limit,
                    indexingCount: indexingCount
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

    @Sendable
    private static func runFollowUpSearch(
        query: String,
        limit: Int,
        indexingCount: Int?
    ) async throws -> RecallSearchResponse {
        let followUp = try RecallIndexingProcess.launch(query: query, limit: limit)
        RecallIndexingProcess.shared = followUp
        let followUpResult = await followUp.waitForResult()

        try Task.checkCancellation()

        switch followUpResult {
        case .launchFailed:
            throw RecallError.notInstalled
        case .cancelled:
            throw CancellationError()
        case let .completed(status, data, _):
            guard status == 0 else {
                let output = String(data: data, encoding: .utf8) ?? ""
                throw RecallError.searchFailed(
                    "recall exited with status \(status): \(output)"
                )
            }

            do {
                let results = try JSONDecoder().decode([RecallResult].self, from: data)
                // Use the indexingCount from the original process (it did the real indexing)
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

// MARK: - RecallIndexingProcess

final class RecallIndexingProcess: @unchecked Sendable {
    nonisolated(unsafe) static var shared: RecallIndexingProcess?

    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let stderrBuffer: StderrBuffer
    private let lock = NSLock()
    private var _result: ProcessResult?
    private var _waiters: [UUID: CheckedContinuation<ProcessResult, Never>] = [:]

    private var _progressCallbacks: [UUID: @Sendable (Int, Int) -> Void] = [:]

    var isRunning: Bool { lock.withLock { _result == nil } }
    var result: ProcessResult? { lock.withLock { _result } }

    var latestDone: Int? { stderrBuffer.indexingDone }
    var latestTotal: Int? { stderrBuffer.indexingTotal }

    func subscribeToProgress(id: UUID, callback: @escaping @Sendable (Int, Int) -> Void) {
        lock.lock()
        _progressCallbacks[id] = callback
        lock.unlock()
    }

    func unsubscribeFromProgress(id: UUID) {
        lock.lock()
        _progressCallbacks.removeValue(forKey: id)
        lock.unlock()
    }

    static func launch(query: String, limit: Int) throws -> RecallIndexingProcess {
        let instance = RecallIndexingProcess(query: query, limit: limit)
        do {
            try instance.process.run()
        } catch {
            throw RecallError.notInstalled
        }
        return instance
    }

    private init(query: String, limit: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["recall", "--json", "-n", "\(limit)", query]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.stderrBuffer = StderrBuffer()

        // Stream stderr for indexing progress
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            if let progress = self.stderrBuffer.append(data) {
                self.lock.lock()
                let callbacks = Array(self._progressCallbacks.values)
                self.lock.unlock()
                for callback in callbacks {
                    callback(progress.done, progress.total)
                }
            }
        }

        // Handle process termination — resume all waiters
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            let data = self.stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let indexingCount = self.stderrBuffer.indexingCount

            let result = ProcessResult.completed(
                status: terminatedProcess.terminationStatus,
                data: data,
                indexingCount: indexingCount
            )

            self.lock.lock()
            self._result = result
            let waiters = self._waiters
            self._waiters.removeAll()
            self._progressCallbacks.removeAll()
            self.lock.unlock()

            for (_, continuation) in waiters {
                continuation.resume(returning: result)
            }
        }
    }

    /// Add a waiter for process completion. If already complete, resumes immediately.
    func addWaiter(_ continuation: CheckedContinuation<ProcessResult, Never>, id: UUID) {
        lock.lock()
        if let result = _result {
            lock.unlock()
            continuation.resume(returning: result)
            return
        }
        _waiters[id] = continuation
        lock.unlock()
    }

    /// Remove a waiter (called on task cancellation). Resumes with `.cancelled`.
    func removeWaiter(id: UUID) {
        lock.lock()
        let cont = _waiters.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(returning: .cancelled)
    }

    /// Non-cancellable wait. Use when you need the result regardless of task cancellation.
    func waitForResult() async -> ProcessResult {
        if let result = self.result { return result }
        return await withCheckedContinuation { continuation in
            addWaiter(continuation, id: UUID())
        }
    }
}

// MARK: - StderrBuffer

private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var _indexingCount: Int?
    private var _indexingDone: Int?
    private var _indexingTotal: Int?

    var indexingCount: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _indexingCount
    }

    var indexingDone: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _indexingDone
    }

    var indexingTotal: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _indexingTotal
    }

    /// Appends data, scans for complete lines, returns indexing progress if found.
    func append(_ data: Data) -> (done: Int, total: Int)? {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)

        // Scan for complete lines
        guard let str = String(data: buffer, encoding: .utf8) else { return nil }
        var result: (done: Int, total: Int)?
        for line in str.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["status"] as? String == "indexing" else { continue }

            if let done = json["done"] as? Int, let total = json["total"] as? Int {
                // Progress update: {"status": "indexing", "done": M, "total": N}
                _indexingDone = done
                _indexingTotal = total
                result = (done: done, total: total)
            } else if let count = json["count"] as? Int {
                // Initial status: {"status": "indexing", "count": N}
                _indexingCount = count
                _indexingDone = 0
                _indexingTotal = count
                result = (done: 0, total: count)
            }
        }
        // Keep only unprocessed partial line (after last newline)
        if let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) {
            buffer = Data(buffer[(lastNewline + 1)...])
        }
        return result
    }
}

// MARK: - ProcessResult

enum ProcessResult: Sendable {
    case launchFailed
    case completed(status: Int32, data: Data, indexingCount: Int?)
    case cancelled
}
