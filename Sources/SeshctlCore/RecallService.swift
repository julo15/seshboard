import Foundation

public enum RecallError: Error {
    case notInstalled
    case timeout
    case searchFailed(String)
}

public struct RecallService: Sendable {

    public static func search(query: String, limit: Int = 10) async throws -> [RecallResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let searchTask = Task.detached { @Sendable () -> [RecallResult] in
            try await runRecallProcess(query: trimmed, limit: limit)
        }

        let timeoutTask = Task.detached { @Sendable () -> [RecallResult] in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            searchTask.cancel()
            throw RecallError.timeout
        }

        do {
            let results = try await searchTask.value
            timeoutTask.cancel()
            return results
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
    private static func runRecallProcess(query: String, limit: Int) async throws -> [RecallResult] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["recall", "--json", "-n", "\(limit)", query]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        // Process.terminate() is thread-safe (sends SIGTERM), so this is safe
        // despite Process not being Sendable.
        nonisolated(unsafe) let unsafeProcess = process

        let result: ProcessResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .launchFailed)
                    return
                }

                process.terminationHandler = { terminatedProcess in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: .completed(
                        status: terminatedProcess.terminationStatus,
                        data: data
                    ))
                }
            }
        } onCancel: {
            unsafeProcess.terminate()
        }

        try Task.checkCancellation()

        switch result {
        case .launchFailed:
            throw RecallError.notInstalled
        case let .completed(status, data):
            guard status == 0 else {
                let output = String(data: data, encoding: .utf8) ?? ""
                throw RecallError.searchFailed(
                    "recall exited with status \(status): \(output)"
                )
            }

            do {
                return try JSONDecoder().decode([RecallResult].self, from: data)
            } catch {
                throw RecallError.searchFailed(
                    "Failed to decode recall output: \(error.localizedDescription)"
                )
            }
        }
    }
}

private enum ProcessResult: Sendable {
    case launchFailed
    case completed(status: Int32, data: Data)
}
