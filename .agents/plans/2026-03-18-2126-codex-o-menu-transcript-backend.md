# Plan: Codex Support For `o` Menu Transcript Detail

## Progress
- [x] Investigate current `o` menu transcript loading flow
- [x] Confirm current Codex session tracking and transcript storage model
- [x] Define minimal architecture for Codex transcript support
- [ ] Implement transcript backend split
- [ ] Add Codex transcript tests
- [ ] Verify `o` detail flow for Claude, Codex, and unsupported tools

## Working Protocol
- Use parallel subagents only for read-only investigation and for running tests; SwiftPM build/test commands must not run concurrently because `.build/` lock contention can hang the repo.
- Keep the DB schema unchanged unless implementation reveals a hard blocker; this plan assumes existing `conversation_id` and `transcript_path` fields are sufficient.
- Mark steps done as implementation lands so a fresh agent can resume from the plan file alone.
- Run targeted tests after each implementation step, then a final full test pass via subagent before closing.
- If Codex transcript files are missing or malformed, preserve the current graceful UI behavior (`No transcript available` / parse failure) rather than adding recovery heuristics in this pass.

## Overview
Add robust support for opening Codex session transcripts from the `o` detail view in Seshboard without widening scope to historical discovery or transcript indexing. The change should stay minimal, but remove the current Claude-centric transcript coupling so Codex support is not implemented as more special cases inside a single parser type.

## User Experience
1. A user runs Codex in a tracked terminal session with Seshboard’s Codex hooks installed.
2. Seshboard continues to show the Codex session in the main list exactly as it does today, using DB session metadata written by hooks.
3. The user presses `o` on that Codex session.
4. Seshboard resolves the transcript file from session metadata, parses the Codex transcript format, and shows readable user/assistant turns in the detail pane.
5. If the session has no transcript path or the file no longer exists, the detail view shows the existing “No transcript available” error rather than a broken or empty UI.
6. Claude sessions continue to open through the same `o` flow with unchanged behavior.
7. Gemini remains unsupported in the detail view, but that unsupported path is handled explicitly through the new transcript loading boundary instead of being implicit in a parser switch.

## Current State
- `o` opens detail through [AppDelegate.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardApp/AppDelegate.swift) and [NavigationState.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardUI/NavigationState.swift), which create a `SessionDetailViewModel` and call `load()`.
- [SessionDetailViewModel.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardUI/SessionDetailViewModel.swift) depends directly on [TranscriptParser.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardCore/TranscriptParser.swift) for both transcript path resolution and parsing.
- `TranscriptParser` is effectively a mixed Claude/Codex implementation:
  - Claude path fallback logic is embedded in `transcriptURL(for:)`.
  - Codex parsing exists in `parseCodex(data:)`.
  - Tool dispatch is done by `parse(data:tool:)` with a `switch` on `SessionTool`.
- Codex sessions are already tracked in the DB by hook scripts in [hooks/codex/session-start.sh](/Users/julianlo/Documents/me/seshboard/hooks/codex/session-start.sh), [hooks/codex/user-prompt.sh](/Users/julianlo/Documents/me/seshboard/hooks/codex/user-prompt.sh), and [hooks/codex/stop.sh](/Users/julianlo/Documents/me/seshboard/hooks/codex/stop.sh).
- The `sessions` table stores metadata only; it does not duplicate transcript contents. Transcript text remains in tool-owned files and is read on demand.
- Current Codex support is incomplete because it depends on hook-provided `transcript_path` and has no dedicated parser/loading tests.

## Proposed Changes
### Transcript Loading Boundary
Introduce a small transcript-loading abstraction in `SeshboardCore` that owns:
- resolving the transcript URL for a given `Session`
- parsing transcript data into `[ConversationTurn]`

This can be implemented as either:
- a lightweight `TranscriptBackend` protocol with a registry keyed by `SessionTool`, or
- a small `TranscriptService` facade with private per-tool backend implementations

The key requirement is to remove tool branching from `SessionDetailViewModel` and stop centralizing all tool logic in one static parser type.

### Claude Backend
Move current Claude-specific behavior into a Claude backend unchanged:
- use explicit `transcriptPath` if present
- otherwise fall back to Claude’s computed `~/.claude/projects/<encoded>/<conversationId>.jsonl` path
- preserve current parsing semantics and existing tests

### Codex Backend
Move current Codex-specific behavior into a Codex backend:
- prefer `session.transcriptPath` as the source of truth
- do not add historical discovery or fallback scanning of `~/.agents/history.jsonl` / `~/.agents/sessions/` in this pass
- keep parsing scoped to the transcript file format already emitted in `~/.agents/sessions/.../rollout-*.jsonl`

### Unsupported Tools
Make unsupported transcript behavior explicit at the backend/service layer so Gemini does not silently fall through a parser switch. `SessionDetailViewModel` should only need to handle:
- no transcript URL available
- parse/load error
- successful turns

### Test Strategy
Expand coverage around:
- Codex transcript parsing
- transcript URL resolution for Codex tracked sessions
- `SessionDetailViewModel` loading Codex transcripts
- unsupported-tool behavior through the new abstraction

## Impact Analysis
- **New Files**: likely per-tool transcript backend files under `Sources/SeshboardCore/` if the backend split is file-based
- **Modified Files**: [TranscriptParser.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardCore/TranscriptParser.swift), [SessionDetailViewModel.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardUI/SessionDetailViewModel.swift), related tests in `Tests/SeshboardCoreTests/` and `Tests/SeshboardUITests/`
- **Dependencies**: relies on existing session metadata already written by Codex hooks; no DB migration expected
- **Similar Modules**: `recall` uses an adapter pattern for Codex/Claude history ingestion, which supports the same direction here without requiring full reuse

## Key Decisions
- Scope is limited to Codex sessions already tracked by Seshboard. This plan intentionally does not discover older or untracked Codex conversations from `~/.agents/history.jsonl`.
- Transcript contents remain external files owned by Claude/Codex. Seshboard stores only metadata pointers in its DB.
- The implementation should stay minimal, but not so minimal that Codex support remains another branch inside a growing parser god-file.

## Implementation Steps

### Step 1: Introduce a Minimal Transcript Backend Boundary
- [ ] Create a transcript service/backend abstraction in `Sources/SeshboardCore/` that can load turns for a `Session`
- [ ] Move tool dispatch out of [SessionDetailViewModel.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardUI/SessionDetailViewModel.swift) so the view model depends on one transcript-loading entry point
- [ ] Keep the public result shape as `[ConversationTurn]` to avoid UI churn

### Step 2: Split Claude And Codex Logic By Backend
- [ ] Extract Claude transcript path resolution and parsing from [TranscriptParser.swift](/Users/julianlo/Documents/me/seshboard/Sources/SeshboardCore/TranscriptParser.swift)
- [ ] Extract Codex transcript path resolution and parsing into a Codex-specific backend that uses `transcriptPath`
- [ ] Make unsupported tools explicit instead of returning an empty parse result from a shared switch

### Step 3: Add Focused Tests
- [ ] Add Codex parser fixtures/tests in `Tests/SeshboardCoreTests/`
- [ ] Add transcript service/backend tests covering Claude fallback path, Codex direct path, and unsupported tools
- [ ] Add/adjust `SessionDetailViewModel` tests in `Tests/SeshboardUITests/` for successful Codex load and missing-transcript cases

### Step 4: Verify End-To-End Behavior
- [ ] Run targeted core/UI tests via subagent
- [ ] Run final full test suite via subagent
- [ ] Manually verify that `o` opens a tracked Codex session transcript from the live local DB without regressing Claude detail view

## Acceptance Criteria
- [ ] [test] Opening `o` on a tracked Codex session with a valid `transcript_path` shows parsed user and assistant turns
- [ ] [test] Opening `o` on a Codex session with no transcript file shows `No transcript available`
- [ ] [test] Claude transcript loading still works, including Claude’s computed-path fallback when `transcriptPath` is absent
- [ ] [test] Unsupported tools are handled explicitly and do not depend on a shared parser returning an empty array
- [ ] The implementation does not add transcript contents to the Seshboard database

## Edge Cases
- Codex sessions created before hooks populated `transcript_path` should continue to fail gracefully rather than triggering directory scans.
- Transcript files may exist but contain partial or malformed JSONL; parsing should fail cleanly with an error instead of crashing the detail view.
- Two tools may share a session list UI, but transcript path semantics remain tool-specific and must not leak into generic UI code.
