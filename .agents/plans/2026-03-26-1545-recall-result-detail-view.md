# Plan: Open Detail View from Recall Results

## Working Protocol
- Sequential implementation — small enough that parallelism isn't needed
- Run tests after each step before moving on
- Build check after modifying core types

## Overview
Allow pressing `o` on recall result rows in search to open the chat detail view, showing the full conversation transcript. Currently `o` only works for session rows.

## User Experience
1. User searches in the session list (pressing `/`)
2. Recall results appear in the "Semantic" section below session matches
3. User navigates to a recall result row with `j`/`k`
4. User presses `o` → the detail view opens showing the full conversation transcript for that session
5. If the transcript file doesn't exist on disk, the detail view shows "No transcript available"
6. User presses `q` to return to the list

## Architecture
**Current flow (sessions):** `o` keypress → `vm.selectedSession` → `navigationState.openDetail(for: session)` → `SessionDetailViewModel(session:)` → `TranscriptParser.transcriptURL(for: session)` → load + parse JSONL → display turns.

**What changes:** The `o` handler adds a fallback branch: if no session is selected, check `vm.selectedRecallResult`. A RecallResult has `sessionId` (= conversationId), `project` (= directory), and `agent` (= tool) — exactly the three fields `TranscriptParser.transcriptURL` needs. We look up the matching Session from the loaded list first (active or recent). If no Session exists in the list, we build the transcript URL directly from RecallResult fields using `TranscriptParser.encodePath` + the standard Claude path convention.

**Key constraint:** `TranscriptParser.transcriptURL(for:)` requires a `Session` object. Rather than constructing a fake Session, we add a new overload `transcriptURL(conversationId:directory:transcriptPath:)` that accepts the raw fields. `SessionDetailViewModel` gets a second initializer that takes a `RecallResult` and computes the URL via this new method.

## Current State
- **`AppDelegate.swift:175-181`** — `o` handler only checks `vm.selectedSession`
- **`SessionListViewModel.swift:291-293`** — `activeSession(for:)` only matches *active* sessions
- **`NavigationState.swift`** — `openDetail(for:)` only accepts `Session`
- **`SessionDetailViewModel.swift`** — initializer requires `Session`, uses it for header display and transcript loading
- **`TranscriptParser.swift:9-19`** — `transcriptURL(for:)` takes a Session, uses `conversationId` + `directory` (+ optional `transcriptPath`)

## Proposed Changes
**Approach:** Extend the existing detail view infrastructure to also accept a RecallResult, rather than creating a separate detail view. The transcript loading logic is identical — only the source of the metadata differs.

1. **TranscriptParser** — Add a static method that takes raw fields (`conversationId`, `directory`) instead of a Session, so we can build the URL from RecallResult data without constructing a fake Session.
2. **SessionDetailViewModel** — Add an initializer that accepts a RecallResult + optional matched Session. Uses the Session if available (for richer header info), falls back to RecallResult fields.
3. **NavigationState** — Add `openDetail(for recallResult:, session:)` method.
4. **AppDelegate** — Extend the `o` handler to check `selectedRecallResult` when no session is selected. Look up matching session from the full list (not just active).
5. **SessionListViewModel** — Add `session(for:)` that finds any session matching a RecallResult (not just active ones).

### Complexity Assessment
**Low.** 4-5 files modified, all following existing patterns. The transcript loading path is unchanged — we're just providing an alternative entry point. No new abstractions needed. Low regression risk since the existing `o`-on-session path is untouched.

## Impact Analysis
- **New Files**: None
- **Modified Files**: `TranscriptParser.swift`, `SessionDetailViewModel.swift`, `NavigationState.swift`, `AppDelegate.swift`, `SessionListViewModel.swift`
- **Dependencies**: RecallResult.agent must map to SessionTool for transcript parsing
- **Similar Modules**: `activeSession(for:)` pattern in SessionListViewModel

## Implementation Steps

### Step 1: Add raw-field transcript URL method to TranscriptParser
- [x] Add `public static func transcriptURL(conversationId: String, directory: String) -> URL?` to `TranscriptParser`
- [x] Refactor existing `transcriptURL(for:)` to delegate to the new method

### Step 2: Add RecallResult support to SessionDetailViewModel
- [x] Add a second initializer: `init(recallResult: RecallResult, session: Session?)` that stores the recall result and optional session
- [x] In `load()`, when initialized from a RecallResult, compute the transcript URL from `recallResult.sessionId` + `recallResult.project` and parse using the tool derived from `recallResult.agent`
- [x] Header display: use Session data if available, fall back to RecallResult fields (project name, agent)

### Step 3: Add RecallResult navigation to NavigationState
- [x] Add `public func openDetail(for recallResult: RecallResult, session: Session?)` that creates a `SessionDetailViewModel(recallResult:session:)` and navigates to `.detail`

### Step 4: Add session lookup and extend `o` handler
- [x] Add `public func session(for result: RecallResult) -> Session?` to SessionListViewModel — matches on `conversationId == result.sessionId` without the `isActive` filter
- [x] In AppDelegate's `o` handler, add an `else if let result = vm.selectedRecallResult` branch that calls `navigationState.openDetail(for: result, session: vm.session(for: result))`

### Step 5: Write tests
- [x] Test `TranscriptParser.transcriptURL(conversationId:directory:)` returns correct path
- [x] Test `SessionDetailViewModel(recallResult:session:)` sets correct state when session is nil
- [x] Test `SessionDetailViewModel(recallResult:session:)` prefers session data when available
- [x] Test `SessionListViewModel.session(for:)` finds matching session (active or inactive)
- [x] Test `SessionListViewModel.session(for:)` returns nil when no match

## Acceptance Criteria
- [ ] [test] Pressing `o` on a recall result opens the detail view with the correct transcript
- [ ] [test] Detail view shows "No transcript available" when transcript file is missing
- [ ] [test] `session(for:)` matches any session by conversationId (not just active)
- [ ] [test-manual] Pressing `o` on a session row still works as before
- [ ] [test-manual] Detail view header shows reasonable info for recall results with and without matching sessions

## Edge Cases
- RecallResult with no matching Session in the loaded list → build URL from RecallResult fields directly, header shows project name + agent
- RecallResult.agent doesn't map to a valid SessionTool → default to `.claude` parsing (recall is a Claude Code feature)
- Transcript file was deleted/cleaned up → detail view shows "No transcript available" error
