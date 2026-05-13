import Foundation
import Testing

@testable import SeshctlCore

// MARK: - Test helpers

/// Walks up from this source file to find the repo root (the directory
/// containing `Package.swift`). Tests use this to locate `hooks/cursor/*.sh`
/// without making assumptions about where the test process's CWD is.
private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #file)
    while url.path != "/" {
        url = url.deletingLastPathComponent()
        let candidate = url.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return url
        }
    }
    fatalError("could not find Package.swift walking up from \(#file)")
}

/// `jq` is required by every Cursor hook script. macOS ships it at
/// `/usr/bin/jq`. Tests gate on its presence with a precondition rather than
/// silently passing — a missing `jq` would mean the hook scripts can't parse
/// the payload and the test would be meaningless.
private let jqPath = "/usr/bin/jq"

private func requireJQ() {
    precondition(FileManager.default.isExecutableFile(atPath: jqPath),
                 "jq missing at \(jqPath); test cannot proceed")
}

/// Per-test scratch directory. Caller is responsible for cleaning it up via
/// `cleanup(_:)` (typically in a `defer`).
private func makeTempDir() throws -> URL {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("seshctl-cursor-hook-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    return temp
}

private func cleanup(_ temp: URL) {
    try? FileManager.default.removeItem(at: temp)
}

/// Writes a bash stub `seshctl-cli` into `dir` that records each argv token
/// on its own line in the file at `$SESHCTL_LOG`. One-arg-per-line keeps
/// argv values with spaces intact when the test reads them back.
private func writeSeshctlStub(in dir: URL) throws -> URL {
    let stub = dir.appendingPathComponent("seshctl-cli")
    let script = """
    #!/bin/bash
    for arg in "$@"; do
      printf '%s\\n' "$arg" >> "$SESHCTL_LOG"
    done
    """
    try Data(script.utf8).write(to: stub)
    try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                          ofItemAtPath: stub.path)
    return stub
}

/// Runs the named Cursor hook script (e.g. `session-start.sh`) under bash
/// with `payload` piped on stdin and `SESHCTL_LOG` pointing at a fresh log
/// file inside `tempDir`. Returns the argv tokens recorded by the stub
/// (one per line). `extraEnv` adds/overrides env vars (e.g. set or omit
/// `CURSOR_PROJECT_DIR`). PATH is rebuilt to put the stub's dir first so
/// `seshctl-cli` resolves to the stub, never a real install.
private func runHook(
    named scriptName: String,
    payload: String,
    tempDir: URL,
    extraEnv: [String: String] = [:]
) throws -> [String] {
    let stubDir = tempDir.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: stubDir, withIntermediateDirectories: true)
    _ = try writeSeshctlStub(in: stubDir)

    let logFile = tempDir.appendingPathComponent("argv.log")
    // Pre-create the log so reads after an early-exit don't throw.
    FileManager.default.createFile(atPath: logFile.path, contents: Data())

    let hookScript = repoRoot()
        .appendingPathComponent("hooks/cursor")
        .appendingPathComponent(scriptName)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = [hookScript.path]

    var env: [String: String] = [
        "PATH": "\(stubDir.path):/usr/bin:/bin",
        "SESHCTL_LOG": logFile.path,
    ]
    for (k, v) in extraEnv {
        env[k] = v
    }
    proc.environment = env

    let inPipe = Pipe()
    proc.standardInput = inPipe
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()

    try proc.run()
    inPipe.fileHandleForWriting.write(Data(payload.utf8))
    try inPipe.fileHandleForWriting.close()
    proc.waitUntilExit()

    let data = try Data(contentsOf: logFile)
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    // Trailing newline from `printf '%s\n'` produces an empty final element;
    // drop it so callers see only real argv tokens.
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { !$0.isEmpty }
}

/// Asserts every token in `expected` appears as its own element in `argv`.
/// Uses contains rather than exact-equality so cosmetic re-ordering of flags
/// in a hook script doesn't churn the tests.
private func expectArgvContains(_ argv: [String], _ expected: [String],
                                sourceLocation: SourceLocation = #_sourceLocation) {
    for token in expected {
        #expect(argv.contains(token),
                "missing argv token: \(token); full argv: \(argv)",
                sourceLocation: sourceLocation)
    }
}

/// Asserts a `--flag value` pair appears adjacent in argv (flag immediately
/// followed by its value). Catches a class of bug where `--dir` and the path
/// could both be present but separated by other flags.
private func expectArgvHasPair(_ argv: [String], flag: String, value: String,
                               sourceLocation: SourceLocation = #_sourceLocation) {
    var found = false
    for i in 0..<argv.count where argv[i] == flag {
        if i + 1 < argv.count, argv[i + 1] == value {
            found = true
            break
        }
    }
    #expect(found,
            "expected adjacent pair \(flag) \(value); full argv: \(argv)",
            sourceLocation: sourceLocation)
}

// MARK: - Captured Cursor payloads
//
// These came from a real Cursor 3.3.30 probe on Julian's machine; the UUIDs
// are real but harmless. Inlined as multi-line string literals — the hooks
// only read what `jq` can pull out, so we don't need separate fixture files.

private let sessionStartPayload = #"""
{"conversation_id":"7edc5650-b588-4218-b258-07e2d9415b27","generation_id":"","model":"default","is_background_agent":false,"composer_mode":"agent","session_id":"7edc5650-b588-4218-b258-07e2d9415b27","hook_event_name":"sessionStart","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"],"user_email":"julian.lo@gmail.com","transcript_path":null}
"""#

private let beforeSubmitPromptPayload = #"""
{"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","generation_id":"86f318c9-c1ae-48aa-82d0-8c7389287a0a","model":"default","composer_mode":"agent","prompt":"hello","attachments":[{"type":"rule","file_path":"AGENTS.md"}],"session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"],"user_email":"julian.lo@gmail.com","transcript_path":null}
"""#

private let afterAgentResponsePayload = #"""
{"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","generation_id":"86f318c9-c1ae-48aa-82d0-8c7389287a0a","model":"default","text":"Hello.","input_tokens":13431,"output_tokens":67,"session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","hook_event_name":"afterAgentResponse","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"],"user_email":"julian.lo@gmail.com","transcript_path":"/Users/julianlo/.cursor/projects/Users-julianlo-Documents-me-recall/agent-transcripts/9b0a3589.jsonl"}
"""#

private let stopPayload = #"""
{"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","status":"completed","loop_count":0,"hook_event_name":"stop","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"],"transcript_path":"/Users/julianlo/.cursor/projects/Users-julianlo-Documents-me-recall/agent-transcripts/9b0a3589.jsonl"}
"""#

private let sessionEndUserClosePayload = #"""
{"conversation_id":"7edc5650-b588-4218-b258-07e2d9415b27","session_id":"7edc5650-b588-4218-b258-07e2d9415b27","reason":"user_close","duration_ms":132279,"is_background_agent":false,"final_status":"completed","hook_event_name":"sessionEnd","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"],"transcript_path":"/Users/julianlo/.cursor/projects/Users-julianlo-Documents-me-recall/agent-transcripts/7edc5650.jsonl"}
"""#

// MARK: - Tests

@Suite("Cursor hook scripts → seshctl-cli argv")
struct CursorHookTests {

    // MARK: session-start

    /// Captures the happy-path argv produced by `session-start.sh` for a real
    /// Cursor sessionStart event. Pins the host-app + workspace + conversation
    /// id wiring and asserts `--pid` is NOT passed (the post-fix behavior:
    /// Cursor's hook subprocess PPIDs aren't stable across events, so keying
    /// on conversation-id is the only safe option).
    @Test("session-start.sh emits expected argv and does NOT pass --pid")
    func sessionStartProducesExpectedArgs() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let argv = try runHook(
            named: "session-start.sh",
            payload: sessionStartPayload,
            tempDir: temp
        )

        expectArgvContains(argv, [
            "start",
            "--tool", "cursor",
            "--dir", "/Users/julianlo/Documents/me/recall",
            "--conversation-id", "7edc5650-b588-4218-b258-07e2d9415b27",
            "--host-app-bundle-id", "com.todesktop.230313mzl4w4u92",
            "--host-app-name", "Cursor",
        ])
        expectArgvHasPair(argv, flag: "--dir",
                          value: "/Users/julianlo/Documents/me/recall")
        expectArgvHasPair(argv, flag: "--conversation-id",
                          value: "7edc5650-b588-4218-b258-07e2d9415b27")

        // Regression: post-fix, the hook MUST NOT pass --pid. Cursor's hook
        // subprocess PPIDs aren't stable across events and can collide across
        // distinct conversations over a long Cursor lifetime.
        #expect(!argv.contains("--pid"),
                "session-start.sh must not pass --pid; full argv: \(argv)")
    }

    // MARK: user-prompt (beforeSubmitPrompt)

    /// `beforeSubmitPrompt` maps to `update --status working --ask <prompt>`,
    /// with workspace + host-app always re-asserted so a lazy-create row is
    /// fully focusable even when sessionStart was missed.
    @Test("user-prompt.sh emits expected argv (update --status working --ask)")
    func beforeSubmitPromptProducesExpectedArgs() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let argv = try runHook(
            named: "user-prompt.sh",
            payload: beforeSubmitPromptPayload,
            tempDir: temp
        )

        expectArgvContains(argv, [
            "update",
            "--tool", "cursor",
            "--conversation-id", "9b0a3589-c574-49d6-a335-ecbb3516db1d",
            "--status", "working",
            "--host-app-bundle-id", "com.todesktop.230313mzl4w4u92",
            "--host-app-name", "Cursor",
            "--dir", "/Users/julianlo/Documents/me/recall",
            "--ask", "hello",
        ])
        expectArgvHasPair(argv, flag: "--status", value: "working")
        expectArgvHasPair(argv, flag: "--ask", value: "hello")
    }

    // MARK: after-agent-response

    /// `afterAgentResponse` writes the model reply and the transcript pointer
    /// onto the row. We pin both adjacent pairs so a future cosmetic shuffle
    /// would fail loudly.
    @Test("after-agent-response.sh emits expected argv (--reply + --transcript-path)")
    func afterAgentResponseProducesExpectedArgs() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let argv = try runHook(
            named: "after-agent-response.sh",
            payload: afterAgentResponsePayload,
            tempDir: temp
        )

        let transcript =
            "/Users/julianlo/.cursor/projects/Users-julianlo-Documents-me-recall/agent-transcripts/9b0a3589.jsonl"

        expectArgvContains(argv, [
            "update",
            "--tool", "cursor",
            "--conversation-id", "9b0a3589-c574-49d6-a335-ecbb3516db1d",
            "--host-app-bundle-id", "com.todesktop.230313mzl4w4u92",
            "--host-app-name", "Cursor",
            "--dir", "/Users/julianlo/Documents/me/recall",
            "--reply", "Hello.",
            "--transcript-path", transcript,
        ])
        expectArgvHasPair(argv, flag: "--reply", value: "Hello.")
        expectArgvHasPair(argv, flag: "--transcript-path", value: transcript)
    }

    // MARK: stop

    /// `stop` flips the row back to idle. No prompt/reply/transcript fields —
    /// just status and the host-app identity for focus.
    @Test("stop.sh emits expected argv (update --status idle)")
    func stopProducesExpectedArgs() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let argv = try runHook(
            named: "stop.sh",
            payload: stopPayload,
            tempDir: temp
        )

        expectArgvContains(argv, [
            "update",
            "--tool", "cursor",
            "--conversation-id", "9b0a3589-c574-49d6-a335-ecbb3516db1d",
            "--status", "idle",
            "--host-app-bundle-id", "com.todesktop.230313mzl4w4u92",
            "--host-app-name", "Cursor",
            "--dir", "/Users/julianlo/Documents/me/recall",
        ])
        expectArgvHasPair(argv, flag: "--status", value: "idle")

        // Sanity: should NOT carry --reply / --ask / --transcript-path.
        #expect(!argv.contains("--reply"))
        #expect(!argv.contains("--ask"))
        #expect(!argv.contains("--transcript-path"))
    }

    // MARK: session-end status mapping

    /// `reason=user_close` is one of the "normal close" enum values and maps
    /// to `completed`.
    @Test("session-end.sh maps reason=user_close → status=completed")
    func sessionEndUserCloseMapsToCompleted() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let argv = try runHook(
            named: "session-end.sh",
            payload: sessionEndUserClosePayload,
            tempDir: temp
        )

        expectArgvContains(argv, [
            "end",
            "--tool", "cursor",
            "--conversation-id", "7edc5650-b588-4218-b258-07e2d9415b27",
            "--status", "completed",
            "--host-app-bundle-id", "com.todesktop.230313mzl4w4u92",
            "--host-app-name", "Cursor",
        ])
        expectArgvHasPair(argv, flag: "--status", value: "completed")
    }

    /// `reason=aborted` (user interrupted the agent mid-loop) maps to
    /// `canceled` — the only path that produces a non-completed final state.
    @Test("session-end.sh maps reason=aborted → status=canceled")
    func sessionEndAbortedMapsToCanceled() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"abc-aborted","session_id":"abc-aborted","reason":"aborted","hook_event_name":"sessionEnd","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"]}
        """#

        let argv = try runHook(
            named: "session-end.sh",
            payload: payload,
            tempDir: temp
        )

        expectArgvContains(argv, ["end", "--status", "canceled"])
        expectArgvHasPair(argv, flag: "--status", value: "canceled")
    }

    /// `reason=error` (agent crashed) also maps to `canceled`.
    @Test("session-end.sh maps reason=error → status=canceled")
    func sessionEndErrorMapsToCanceled() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"abc-error","session_id":"abc-error","reason":"error","hook_event_name":"sessionEnd","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"]}
        """#

        let argv = try runHook(
            named: "session-end.sh",
            payload: payload,
            tempDir: temp
        )

        expectArgvContains(argv, ["end", "--status", "canceled"])
        expectArgvHasPair(argv, flag: "--status", value: "canceled")
    }

    /// The explicit wildcard fallback in `session-end.sh`'s case statement
    /// means any unknown future `reason` value defaults to `completed`, not
    /// `canceled`. Pins the safer of the two failure modes (rather than
    /// marking sessions canceled on benign future enum additions).
    @Test("session-end.sh maps unknown reason → status=completed (wildcard fallback)")
    func sessionEndUnknownReasonMapsToCompleted() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"abc-weird","session_id":"abc-weird","reason":"weird_unknown_value","hook_event_name":"sessionEnd","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"]}
        """#

        let argv = try runHook(
            named: "session-end.sh",
            payload: payload,
            tempDir: temp
        )

        expectArgvContains(argv, ["end", "--status", "completed"])
        expectArgvHasPair(argv, flag: "--status", value: "completed")
    }

    // MARK: early-exit guards

    /// `is_background_agent=true` short-circuits every hook — Cursor's
    /// background agents run in CI-like environments and shouldn't pollute
    /// the local session list. We confirm no argv was recorded at all.
    @Test("Background-agent payloads short-circuit before calling seshctl-cli")
    func backgroundAgentSkipsEarlyExit() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","generation_id":"86f318c9-c1ae-48aa-82d0-8c7389287a0a","model":"default","composer_mode":"agent","prompt":"hello","is_background_agent":true,"session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.3.30","workspace_roots":["/Users/julianlo/Documents/me/recall"]}
        """#

        let argv = try runHook(
            named: "user-prompt.sh",
            payload: payload,
            tempDir: temp
        )

        #expect(argv.isEmpty,
                "background-agent payload must not call seshctl-cli; argv: \(argv)")
    }

    /// Update-style hooks early-exit when both `workspace_roots[0]` is empty
    /// AND `CURSOR_PROJECT_DIR` is unset — without a workspace, the lazy-
    /// create branch in `seshctl-cli update` would land on a bogus row.
    /// Pins the (C3) early-exit added in the fixes.
    @Test("Empty workspace + unset CURSOR_PROJECT_DIR short-circuits update hooks")
    func emptyWorkspaceSkipsEarlyExit() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","prompt":"hello","session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.3.30","workspace_roots":[]}
        """#

        // Deliberately omit CURSOR_PROJECT_DIR from extraEnv so the hook sees
        // it as unset. The child process's environment is the explicit dict
        // we pass — no inheritance from the parent test process.
        let argv = try runHook(
            named: "user-prompt.sh",
            payload: payload,
            tempDir: temp
        )

        #expect(argv.isEmpty,
                "empty workspace + unset CURSOR_PROJECT_DIR must not call seshctl-cli; argv: \(argv)")
    }

    /// When `workspace_roots` is empty BUT the parent env supplies
    /// `CURSOR_PROJECT_DIR`, the fallback kicks in and the hook proceeds
    /// using the env var as `--dir`. Pins that the early-exit only fires
    /// when BOTH sources of workspace are missing.
    @Test("Empty workspace + CURSOR_PROJECT_DIR set uses env var as --dir")
    func cursorProjectDirFallbackUsed() throws {
        requireJQ()
        let temp = try makeTempDir()
        defer { cleanup(temp) }

        let payload = #"""
        {"conversation_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","prompt":"hello","session_id":"9b0a3589-c574-49d6-a335-ecbb3516db1d","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.3.30","workspace_roots":[]}
        """#

        let fallbackDir = "/some/fallback/path"
        let argv = try runHook(
            named: "user-prompt.sh",
            payload: payload,
            tempDir: temp,
            extraEnv: ["CURSOR_PROJECT_DIR": fallbackDir]
        )

        expectArgvContains(argv, ["--dir", fallbackDir])
        expectArgvHasPair(argv, flag: "--dir", value: fallbackDir)
    }
}
