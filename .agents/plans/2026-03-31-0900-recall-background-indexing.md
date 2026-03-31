# Plan: Reuse in-flight recall process across search sessions

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them
- Run tests after each step before moving on
- Build only — do not install (another agent handles installs)

## Overview
When the user escapes a search while recall is indexing, the process is killed and all indexing progress is lost. The next search re-indexes from scratch (~50 seconds for 8000 entries). Fix by keeping the recall process alive across search sessions and reusing it when the user searches again.

## User Experience
1. User presses `/`, types a query. Recall starts indexing — UI shows "Indexing 128/8000 entries..."
2. User presses Escape. The indexing indicator disappears, search closes. **Recall keeps running in the background.**
3. User presses `/` again, types a query. The UI immediately shows "Indexing 4500/8000 entries..." — picking up progress from the still-running process.
4. Indexing finishes. Results appear. Subsequent searches are instant (no indexing needed).
5. If the user never re-searches, the background process finishes silently — cursors/embeddings are saved for next time.

## Architecture

### Current runtime behavior
1. User types query → 300ms debounce → `executeRecallSearch()` creates a Task
2. Task calls `RecallService.search()` which spawns a `recall --json` process
3. `readabilityHandler` streams stderr for indexing progress → callback → main actor → UI
4. Process exits → stdout parsed as JSON → results returned
5. On escape: `exitSearch()` → `recallSearchTask.cancel()` → `process.terminate()` → SIGTERM kills recall → cursors not saved

### What changes
- **New: `RecallIndexingProcess` actor** in `RecallService.swift` — owns a single in-flight recall process. It's an actor (not a struct) because it manages mutable shared state (the running process, its stderr stream, and progress) that must be accessed from multiple tasks safely.
- When `RecallService.search()` starts, it checks `RecallIndexingProcess.shared` for a running process. If one exists and is still indexing, it subscribes to its progress and waits for it to finish, then runs a fast search-only call.
- On Task cancellation (escape/timeout), the process is NOT terminated. Instead, the Task just stops observing. The process continues to completion.
- The process is only terminated when a new search starts with different parameters AND the old process is still indexing (unlikely — reindexing the same data).
- `RecallIndexingProcess` publishes progress via an `AsyncStream<(done: Int, total: Int)>` that any subscriber can listen to.

### What stays the same
- `SessionListViewModel` still calls `RecallService.search(query:onIndexing:)` with the same signature
- The Python `recall` CLI is unchanged
- `StderrBuffer`, `ProcessResult`, and the process spawning logic stay in `RecallService`

## Current State
- **`RecallService.swift`**: Static service, spawns a new `Process` per search. Uses `withTaskCancellationHandler` to terminate on cancel. Has `StderrBuffer` for streaming stderr, `onIndexing` callback for progress.
- **`SessionListViewModel.swift`**: `executeRecallSearch()` creates a Task, calls `RecallService.search()`, sets UI state from response. `exitSearch()` cancels the task (which kills the process). `recallSearchGeneration` guards against stale callbacks.
- **`recall` CLI**: Emits `{"status": "indexing", "count": N}` then per-batch `{"status": "indexing", "done": M, "total": N}` on stderr. Saves cursors/embeddings at the end of `build_index()`.

## Proposed Changes

### RecallService: Add `RecallIndexingProcess` actor
Introduce a lightweight actor that owns the in-flight recall process. It:
1. Stores the running `Process` and its pipes
2. Publishes progress via `AsyncStream`
3. Exposes `waitForCompletion() async throws -> Data` (returns stdout)
4. Is NOT killed on Task cancellation — lives until the process exits naturally
5. Is replaced when a new indexing run starts

`RecallService.search()` changes:
- Before spawning a new process, check if `RecallIndexingProcess.shared` is running
- If running: subscribe to its progress stream (forwarding to `onIndexing`), wait for it to finish, then decode results from its stdout OR run a quick follow-up search (since indexing is done, this takes <1 second)
- If not running: spawn a new process as before, but wrap it in a `RecallIndexingProcess` and store it as `shared`
- On cancellation: detach from the process (stop observing), but don't terminate it

### SessionListViewModel: Minimal changes
- `exitSearch()`: stop cancelling `recallSearchTask` with prejudice — let it detach gracefully
- Actually, we CAN still cancel the task. The difference is that RecallService's cancellation handler no longer kills the process. The ViewModel doesn't need to know about this.

### Complexity Assessment
**Medium.** Touches 1-2 files (RecallService.swift primarily, minor ViewModel cleanup). Introduces one new type (`RecallIndexingProcess` actor). The tricky part is the lifecycle management — ensuring the shared process is properly cleaned up on exit, and that concurrent access from multiple search tasks is safe. The actor model handles concurrency, and the process self-cleans via its termination handler.

## Impact Analysis
- **New Types**: `RecallIndexingProcess` actor (in RecallService.swift, ~60 lines)
- **Modified Files**: `Sources/SeshctlCore/RecallService.swift` (major — new actor, reworked `search()`), `Sources/SeshctlUI/SessionListViewModel.swift` (minor — remove process-killing from exit)
- **Dependencies**: Recall CLI stderr contract (unchanged)
- **Similar Modules**: None — this is the only subprocess reuse pattern in the codebase

## Implementation Steps

### Step 1: Add `RecallIndexingProcess` actor
- [x] Create `RecallIndexingProcess` actor in `RecallService.swift` with:
  - `nonisolated(unsafe) static var shared: RecallIndexingProcess?`
  - Stored `Process`, stdout/stderr pipes, `StderrBuffer`
  - `progress: AsyncStream<(done: Int, total: Int)>` and its continuation
  - `waitForCompletion() async -> ProcessResult`
  - `isRunning: Bool` computed property
  - Process termination handler that finishes the stream and stores the result
- [x] Move process spawning logic from `runRecallProcess()` into `RecallIndexingProcess.init()`

### Step 2: Rework `RecallService.search()` to reuse in-flight process
- [x] At the start of `runRecallProcess()`: check `RecallIndexingProcess.shared`
  - If running: subscribe to its progress (forwarding to `onIndexing`), await completion
  - If not running or finished: spawn new process, store as `.shared`
- [x] Change `onCancel` in `withTaskCancellationHandler`: do NOT terminate the process. Just stop observing.
- [x] After process completes (reused or new): if stdout has results, decode and return. If not (e.g., reused process had a different query), run a quick follow-up search (indexing is done, will be fast).

### Step 3: Clean up ViewModel
- [x] In `exitSearch()`: keep cancelling `recallSearchTask` (this is fine — it just stops the Task, no longer kills the process)
- [x] Remove debug logging (the `vmLog.error` and `recallLog.error` calls added for debugging)

### Step 4: Tests
- [x] Test `RecallIndexingProcess` lifecycle: create, check `isRunning`, await completion
- [x] Test that cancelling a search Task does not terminate the underlying process
- [x] Test that a second `search()` call reuses the in-flight process (receives progress from it)
- [x] Test that after process completes, `shared` is cleared or next call spawns fresh
- [x] Update existing `RecallServiceTests` for new behavior
- [x] Build and verify: `swift build 2>&1`

## Acceptance Criteria
- [x] [test] Cancelling a search task does not send SIGTERM to the recall process
- [x] [test] A second search call reuses an in-flight indexing process
- [x] [test] Progress updates from a reused process are forwarded to the new caller's `onIndexing`
- [ ] [test-manual] Escape during indexing → re-search shows continued progress (not restart)
- [ ] [test-manual] Indexing completes in background after escape → next search returns instant results
- [x] Existing recall search behavior unchanged when no indexing is needed

## Edge Cases
- **Process finishes between searches**: `shared` holds the completed result briefly. Next search sees it's not running, spawns fresh (which finds nothing to index). Fast path.
- **Two rapid searches with different queries**: Both need the same indexing work. Second search reuses the in-flight process. After indexing, the search-only step uses the second query. Correct results.
- **App quit during background indexing**: Process is orphaned. Acceptable — it finishes, saves cursors, exits. No resource leak beyond the process runtime.
- **Recall not installed**: `RecallIndexingProcess` never created. Falls through to `RecallError.notInstalled` as before.
- **Process crashes mid-indexing**: Termination handler fires, completion result has non-zero status. Next search spawns fresh. Same as today.
