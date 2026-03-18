# Plan: Codex CLI Integration

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on
- If blocked, document the blocker here before stopping
- Build timeout: 120s. Test timeout: 30s. Run `make kill-build` if hung.

## Overview
Add Codex CLI support to seshboard so Codex sessions appear alongside Claude sessions with status tracking and transcript viewing. Codex has an experimental hooks engine (v0.114+, feature flag `codex_hooks`) that supports `SessionStart`, `UserPromptSubmit`, and `Stop` events — the same model as Claude Code. Hook scripts receive JSON on stdin with `session_id`, `cwd`, `transcript_path`, `prompt` (on UserPromptSubmit), and `last_assistant_message` (on Stop).

## Current State
- `SessionTool.codex` already exists in the enum — no model changes needed
- All CLI commands already accept `--tool codex` — the plumbing is there
- Claude hooks live in `hooks/claude/` with install logic in `scripts/install-hooks.sh` and `Sources/seshboard-cli/Install.swift`
- Transcript parsing (`TranscriptParser.swift`) and detail view (`SessionDetailViewModel.swift`) are Claude-only
- `TranscriptParser.transcriptURL(for:)` hardcodes Claude's `~/.claude/projects/` path convention

## Key Decisions
- **Codex hooks require a feature flag**: `codex_hooks = true` in `~/.agents/config.toml`. The install process must enable this.
- **Codex config home is `~/.agents/`** (not `~/.codex/`). Hooks go in `~/.agents/hooks.json`.
- **Codex hooks.json uses PascalCase** event names (`SessionStart`, `UserPromptSubmit`, `Stop`) — confirmed by testing.
- **Codex transcripts** are at `~/.agents/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl`. The `transcript_path` is provided in the hook payload, so we store it on the session and use it directly rather than computing it.
- **Codex transcript format** is different from Claude's: JSONL with `type` field values like `session_meta`, `event_msg`, `response_item`, `turn_context`. User messages are in `response_item` entries with `role: "user"`, assistant messages in `response_item` with `role: "assistant"`. Tool calls appear as `event_msg` with `type: "tool_use"`.
- **No SessionEnd hook in Codex** — the `Stop` event fires when the agent finishes a turn but the session may continue. We'll use `Stop` to set status to `idle` (same as Claude). Session cleanup relies on the existing GC/stale-detection logic.
- **No Notification hook in Codex** — there's no equivalent of Claude's "waiting for approval" event. We skip the `waiting` status for Codex sessions.

## Implementation Steps

### Step 1: Add `transcriptPath` field to Session model
Store the transcript path directly on the session (provided by Codex hook payload), so we don't need tool-specific path computation.

- [x] Add `transcriptPath` optional String column to `Session` in `Sources/SeshboardCore/Session.swift`
- [x] Add migration in `Sources/SeshboardCore/Database.swift` to add `transcript_path` column
- [x] Add `--transcript-path` option to `start` and `update` CLI commands in `Sources/seshboard-cli/SeshboardCLI.swift`
- [x] Pass `transcriptPath` through to database insert/update

### Step 2: Create Codex hook scripts
Mirror the Claude hook scripts but adapted for Codex's JSON payload format.

- [x] Create `hooks/codex/session-start.sh` — parse stdin JSON for `session_id`, `cwd`, `transcript_path`; call `seshboard-cli start --tool codex --conversation-id <session_id> --dir <cwd> --pid $PPID --transcript-path <path>`
- [x] Create `hooks/codex/user-prompt.sh` — parse stdin JSON for `prompt`; call `seshboard-cli update --tool codex --pid $PPID --status working --ask <prompt>`
- [x] Create `hooks/codex/stop.sh` — call `seshboard-cli update --tool codex --pid $PPID --status idle`
- [x] Ensure all scripts are executable and use `set -euo pipefail`

### Step 3: Add Codex hook installation
Add install/uninstall logic for Codex hooks in `~/.agents/hooks.json`.

- [x] Create `scripts/install-codex-hooks.sh` — copies hook scripts to `~/.local/share/seshboard/hooks/codex/`, upserts entries in `~/.agents/hooks.json`, ensures `codex_hooks = true` in `~/.agents/config.toml`
- [x] Add `--codex` flag to `Install` and `Uninstall` commands in `Sources/seshboard-cli/Install.swift`
- [x] Update `--all` flag to include Codex
- [x] Update `scripts/install-hooks.sh` to also call Codex install (or make a unified script)
- [x] Update `Makefile` `install-hooks` target

### Step 4: Support Codex transcripts in TranscriptParser
Make transcript loading work for Codex sessions using the stored `transcriptPath`.

- [x] Add `TranscriptParser.transcriptURL(for:)` fallback: if `session.transcriptPath` is set, use it directly
- [x] Add `TranscriptParser.parseCodex(data:)` method to parse Codex's JSONL format (extract `response_item` entries with user/assistant roles)
- [x] Update `SessionDetailViewModel.load()` to support both Claude and Codex sessions (remove the `guard session.tool == .claude` check, dispatch to appropriate parser)

### Step 5: Update UI and install targets
- [x] Update `Makefile` help text for `install-hooks` to mention Codex
- [x] Update `AGENTS.md` / `CLAUDE.md` to document `make install-hooks` now covers Codex too

## Acceptance Criteria
- [x] Running `make install-hooks` registers hooks in both `~/.claude/settings.json` and `~/.agents/hooks.json`
- [x] Starting a Codex interactive session creates a seshboard session visible in the panel
- [x] Codex sessions show status transitions: working → idle
- [x] User prompts in Codex sessions appear as `lastAsk` in the session list
- [x] Opening a Codex session detail view shows the conversation transcript
- [x] `seshboard-cli list --tool codex` filters to Codex sessions only
- [x] Claude integration continues to work unchanged
- [x] All existing tests pass

## Edge Cases
- `~/.agents/` directory may not exist if Codex was never used — install script should handle this gracefully
- `~/.agents/config.toml` may not exist or may have existing content — install must merge, not overwrite
- `~/.agents/hooks.json` may not exist — install creates it; may have existing hooks — install merges
- Codex `exec` mode fires `SessionStart` and `Stop` but not `UserPromptSubmit` — sessions from exec mode will have no `lastAsk` (acceptable)
- Codex `codex_hooks` feature flag is "under development" — if OpenAI changes the API, hooks may break. Document this as experimental.
