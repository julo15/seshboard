# Plan: Show recall indexing status in seshboard

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them
- Run tests after each step before moving on
- Build only — do not install (another agent handles installs)

## Overview
When `recall` indexes new entries before searching, seshboard shows only "Searching..." with no indication that indexing is happening. This can be confusing since indexing takes noticeably longer than a regular search. Fix by having `recall` output structured JSON status to stderr in `--json` mode, and having seshboard capture and display it.

## User Experience
1. User presses `/` and types a search query
2. If recall needs to index new entries, the UI shows **"Indexing 12 entries..."** instead of "Searching..."
3. Once indexing completes and search results arrive, the indicator disappears as normal

## Current State
- **recall** (`../recall/recall/index.py:86`): Prints `Indexing {count} new entries...` as plain text to stderr
- **recall** (`../recall/recall/cli.py:122`): Routes status messages to stderr in JSON mode, stdout otherwise
- **seshboard** (`RecallService.swift:62`): Sets `process.standardError = FileHandle.nullDevice` — stderr is discarded
- **seshboard** (`SessionListViewModel.swift:19`): Has `isRecallSearching: Bool` but no indexing-specific state
- **seshboard** (`SessionListView.swift:118-128`): Shows `ProgressView()` + "Searching..." when `isRecallSearching`

## Proposed Changes

### recall (Python)
Change `index.py` to output JSON to stderr when a caller signals JSON mode. The simplest approach: `build_index()` already prints to stderr. Change it to emit `{"status": "indexing", "count": N}` as a JSON line to stderr. Since `build_index` doesn't know about `--json` mode, pass a `json_status` parameter (defaulting to `False`) and have `cli.py` pass `True` when `args.json_output` is set. Non-JSON mode keeps the human-readable message.

### seshboard (Swift)
1. Capture stderr from the recall process alongside stdout
2. Parse any `{"status": "indexing", "count": N}` line from stderr
3. Expose indexing count as `recallIndexingCount: Int?` on the view model
4. Update the UI to show "Indexing N entries..." when set

## Impact Analysis
- **Modified Files (recall)**: `recall/index.py`, `recall/cli.py`
- **Modified Files (seshboard)**: `Sources/SeshctlCore/RecallService.swift`, `Sources/SeshctlUI/SessionListViewModel.swift`, `Sources/SeshctlUI/SessionListView.swift`
- **Dependencies**: seshboard depends on recall's stderr output format (new JSON contract)
- **Similar Modules**: None — this is the only subprocess communication path

## Implementation Steps

### Step 1: Update recall to emit JSON status on stderr
- [x] In `recall/index.py`, add `json_status: bool = False` param to `build_index()`. When `True` and indexing, print `{"status": "indexing", "count": N}` to stderr instead of the plain text message
- [x] In `recall/cli.py`, pass `json_status=args.json_output` to both `build_index()` calls (lines 127 and 152)
- [x] Add tests for the JSON status output

### Step 2: Capture stderr in RecallService
- [x] In `RecallService.swift`, add a stderr `Pipe` instead of `FileHandle.nullDevice`
- [x] Read stderr data alongside stdout in the completion handler
- [x] Parse `{"status": "indexing", "count": N}` from stderr
- [x] Add `indexedCount: Int?` to a new `RecallSearchResult` struct (or return a tuple) so callers get both results and indexing info
- [x] Update `RecallResult.swift` or add a wrapper type

### Step 3: Expose indexing state in SessionListViewModel
- [x] Add `@Published var recallIndexingCount: Int?` property
- [x] In `executeRecallSearch()`, set `recallIndexingCount` from the parsed stderr before results arrive, clear it when search completes

### Step 4: Update SessionListView to show indexing status
- [x] When `recallIndexingCount != nil`, show "Indexing N entries..." instead of "Searching..."
- [x] Keep the existing `ProgressView()` spinner

### Step 5: Tests
- [x] Test `RecallService` stderr parsing (indexing JSON present, absent, malformed)
- [x] Test `SessionListViewModel` indexing state transitions
- [x] Build and verify: `swift build 2>&1`

## Acceptance Criteria
- [x] [test] When recall indexes entries in `--json` mode, stderr contains `{"status": "indexing", "count": N}`
- [x] [test] When recall has nothing to index, no indexing status is emitted
- [x] [test] Non-JSON mode still shows the human-readable "Indexing X new entries..." message
- [x] [test] `RecallService` correctly parses indexing count from stderr
- [x] [test] `RecallService` handles missing/malformed stderr gracefully (returns nil count)
- [x] UI shows "Indexing N entries..." when recall is indexing, "Searching..." otherwise
- [x] Existing recall search behavior is unchanged (results, timeouts, error handling)

## Edge Cases
- Recall has nothing to index → no stderr JSON → UI shows "Searching..." as before
- Malformed stderr → ignore, treat as no indexing info
- Recall prints indexing status but then fails → `isRecallSearching` clears normally on error, `recallIndexingCount` clears too
