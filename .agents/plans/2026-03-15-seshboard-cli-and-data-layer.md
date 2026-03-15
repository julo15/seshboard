# Seshboard

A macOS tool to track and manage active Claude/LLM CLI sessions with an MRU widget.

## Overview

Seshboard helps you keep track of all your LLM CLI interactions (Claude Code, Gemini, Codex) by logging session events to a local database and surfacing them via a lightweight floating panel (or macOS widget).

## Architecture

```
CLI hooks → `seshboard-cli` → SQLite DB (via SeshboardCore) ← macOS app (reads)
```

### Components

1. **`seshboard-cli`** — lightweight command-line tool that records session events
2. **Shared data layer** — Swift package with SQLite schema, queries, and models (shared between CLI and UI)
3. **CLI integrations** — native hooks for Claude Code, Gemini CLI, and Codex CLI
4. **UI** (Phase 2) — floating panel (Spotlight-style) or macOS WidgetKit widget

## Phase 1: CLI + Data Layer

### 1.0 — Hook Payload Discovery

Before building integrations, verify what data each CLI actually sends in hook payloads:

1. Write minimal test hooks for each CLI that dump the full JSON payload to a file
2. Run a short interaction with each CLI
3. Inspect payloads to determine:
   - Is the user's message/prompt included?
   - Is a conversation/session ID exposed?
   - Is the working directory included?
   - What's the PID situation (own PID, parent PID)?
4. Document findings and adjust the integration design accordingly

This is a prerequisite — the hook integration design depends on what's actually in the payloads.

### 1.1 — SQLite Database

Location: `~/.local/share/seshboard/seshboard.db` (XDG-style)

Schema:
```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,            -- UUID
  conversation_id TEXT,           -- CLI's own conversation/session ID (if available)
  tool TEXT NOT NULL,             -- claude | gemini | codex
  directory TEXT NOT NULL,        -- working directory
  last_ask TEXT,                  -- most recent user message (truncated to 500 chars)
  status TEXT NOT NULL DEFAULT 'idle',  -- idle | working | completed | canceled | stale
  pid INTEGER,                   -- CLI process PID for window focusing
  window_id TEXT,                -- optional window identifier for tap-to-focus
  started_at TEXT NOT NULL,       -- ISO 8601
  updated_at TEXT NOT NULL        -- ISO 8601
);

CREATE INDEX idx_sessions_updated_at ON sessions(updated_at DESC);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_conversation ON sessions(conversation_id);
CREATE INDEX idx_sessions_pid_tool ON sessions(pid, tool);
```

WAL mode enabled by default for concurrent read/write safety (UI reads while hooks write).

#### Statuses

| Status | Meaning | Set by |
|---|---|---|
| **idle** | Waiting for user input | Session start, after LLM responds |
| **working** | LLM is generating/executing | User sends a message |
| **completed** | Ended normally | Stop/SessionEnd hook |
| **canceled** | User killed it | Stop hook with cancel signal |
| **stale** | Presumed crashed | `gc` detects PID is dead while status is idle/working |

#### Conversation Continuity

Multiple sessions can share the same `conversation_id` (e.g., `claude --continue` creates a new PID/session but continues the same conversation). The UI can group or annotate these.

If the hook payload exposes a conversation ID, use it. Otherwise, each invocation is an independent session.

### 1.2 — `seshboard-cli`

Written in: **Swift** (single binary, shares data layer with the Phase 2 macOS app)

Dependencies:
- **swift-argument-parser** — CLI argument parsing
- **GRDB** — SQLite access (shared with the macOS app in Phase 2)

Project structure:
```
Package.swift              — Swift package manifest
Sources/
  SeshboardCore/           — shared data layer (models, DB, queries)
  seshboard-cli/           — CLI executable (thin wrapper over SeshboardCore)
```

The `SeshboardCore` package is the shared foundation — both the CLI and the future macOS app depend on it. This avoids rewriting the DB layer in a different language.

All commands that write to the DB must be non-blocking with a short timeout (2s max). Hooks must never stall the LLM CLI.

#### Session Addressing

Commands use `--pid <pid> --tool <tool>` to look up sessions. This is the natural addressing scheme for hooks, which don't have a way to stash a session ID between events. The internal UUID is used for storage and the `show` command.

Commands:
```
seshboard-cli start --tool <tool> --dir <dir> --pid <pid> [--conversation-id <id>]
  → Creates a new session, prints session ID to stdout
  → If an active session exists for this pid+tool, ends it first

seshboard-cli update --pid <pid> --tool <tool> [--ask <message>] [--status <status>]
  → Updates the active session for this pid+tool
  → If no active session exists, creates one (idempotent)

seshboard-cli end --pid <pid> --tool <tool> [--status <status>]
  → Ends the active session (defaults to status=completed)

seshboard-cli list [--limit <n>] [--status <status>] [--tool <tool>]
  → Lists sessions ordered by updated_at DESC (default limit: 20)

seshboard-cli show <id>
  → Shows full details for a session by UUID

seshboard-cli gc [--older-than <duration>]
  → Garbage collect old completed sessions (default: 30d)
  → Also reaps stale sessions: marks idle/working sessions as "stale"
    if their PID is no longer alive

seshboard-cli install [--claude] [--gemini] [--codex] [--all]
  → Installs hooks into CLI configs (see §1.4)

seshboard-cli uninstall [--claude] [--gemini] [--codex] [--all]
  → Removes hooks from CLI configs
```

### 1.3 — Hook Integration

All three LLM CLIs support native hooks — no wrapper scripts needed. Hooks fire automatically during normal CLI usage — zero friction.

#### Hook Scripts

Each hook is a small shell script that:
1. Reads JSON payload from stdin
2. Extracts relevant fields (message, status, etc.)
3. Calls `seshboard-cli` with appropriate arguments
4. Exits quickly (must not block the CLI)

Scripts live in `~/.local/share/seshboard/hooks/` and are installed by `seshboard-cli install`.

#### Claude Code

Hooks configured in `~/.claude/settings.json` (or project-level `.claude/settings.json`):

| Event | Hook | Seshboard action |
|---|---|---|
| Session start | `SessionStart` | `seshboard-cli start --tool claude --dir <cwd> --pid $PPID --conversation-id <session_id>` |
| User message | `UserPromptSubmit` | `seshboard-cli update --pid $PPID --tool claude --ask "<prompt>" --status working` |
| LLM done | `Stop` | `seshboard-cli update --pid $PPID --tool claude --status idle` |
| Session end | `SessionEnd` | `seshboard-cli end --pid $PPID --tool claude` |

All hook payloads include `session_id`, `cwd`, and `hook_event_name` as common fields. `UserPromptSubmit` adds `prompt`. See `.agents/discovery/claude-code-payloads.md` for full payload docs.

#### Gemini CLI

Hooks configured in `~/.gemini/settings.json` (or project-level `.gemini/settings.json`):

| Event | Hook | Seshboard action |
|---|---|---|
| Session start | `SessionStart` | `seshboard-cli start --tool gemini --dir <cwd> --pid $PPID --conversation-id <session_id>` |
| User message | `BeforeAgent` | `seshboard-cli update --pid $PPID --tool gemini --ask "<prompt>" --status working` |
| LLM done | `AfterAgent` | `seshboard-cli update --pid $PPID --tool gemini --status idle` |
| Session end | `SessionEnd` | `seshboard-cli end --pid $PPID --tool gemini` |

Payloads include `session_id`, `cwd`, `timestamp` as common fields. `BeforeAgent` adds `prompt`. See `.agents/discovery/gemini-cli-payloads.md`.

#### Codex CLI

Hooks configured in `~/.codex/hooks.json` (or project-level `.codex/hooks.json`):

| Event | Hook | Seshboard action |
|---|---|---|
| Session start | `SessionStart` | `seshboard-cli start --tool codex --dir <cwd> --pid $PPID --conversation-id <session_id>` |
| Turn complete | `Stop` | `seshboard-cli update --pid $PPID --tool codex --status idle` |

**Limitations:** Codex CLI only fires `SessionStart` and `Stop`. No `UserPromptSubmit` hook is wired up, so `last_ask` won't be populated. `Stop` fires on every turn completion — can't distinguish turn-end from session-end. Rely on `gc` to reap stale sessions when PID dies. See `.agents/discovery/codex-cli-payloads.md`.

### 1.4 — `seshboard-cli install` Command

The `install` command automates hook setup:

1. **Detects** existing config files for each CLI
2. **Backs up** current configs before modifying (`.bak` with timestamp)
3. **Injects** seshboard hook entries into the appropriate config format
4. **Validates** the resulting config is valid JSON
5. **Installs** hook scripts to `~/.local/share/seshboard/hooks/`
6. **Reports** what was installed

```
$ seshboard-cli install --all
✓ Claude Code: added hooks to ~/.claude/settings.json
✓ Gemini CLI: added hooks to ~/.config/gemini/settings.json
✓ Codex CLI: added hooks to ~/.codex/hooks.json
✓ Hook scripts installed to ~/.local/share/seshboard/hooks/
```

`seshboard-cli uninstall` reverses this cleanly, removing only seshboard-specific hooks.

### 1.5 — Testing

All tests use Swift's built-in `XCTest` framework. Each test gets a fresh in-memory (or temp file) SQLite database — no shared state between tests.

#### SeshboardCore tests (`Tests/SeshboardCoreTests/`)

- **Database layer**: create/open DB, WAL mode enabled, schema migration runs on fresh DB
- **Session CRUD**: `start` creates a session, `update` modifies fields, `end` sets terminal status
- **Session addressing**: lookup by pid+tool, idempotent `start` (ends existing session for same pid+tool)
- **Conversation continuity**: multiple sessions can share a `conversation_id`
- **Status transitions**: idle → working → idle, idle → completed, working → canceled
- **Edge cases**: `update` with no active session creates one, `end` on already-ended session is a no-op
- **Queries**: `list` ordering, filtering by status/tool, limit, `show` by UUID
- **GC**: completed sessions older than threshold are deleted, stale detection (mock PID checks)

#### CLI integration tests (`Tests/CLITests/`)

- **End-to-end**: invoke the built binary with real arguments, verify stdout/stderr and exit codes
- **Round-trip**: `start` → `list` → `show` → `update` → `end` → verify final state

### 1.6 — Implementation Order

1. **Hook payload discovery** (§1.0) — test hooks, document payloads, validate assumptions
2. Swift package setup (`Package.swift`, directory structure, dependencies)
3. SQLite database layer + tests (schema, migrations, WAL mode)
4. Core CLI commands + tests (`start`, `update`, `end`, `list`, `show`)
5. Claude Code hook scripts + `install --claude`
6. Gemini hook scripts + `install --gemini`
7. Codex hook scripts + `install --codex`
8. `gc` command + tests (including stale session reaping)
9. CLI integration tests

## Phase 2: UI (future)

Two options under consideration:

### Option A: Floating Panel (preferred)

Spotlight-style ephemeral window:
- `NSPanel` with `.nonactivatingPanel` — doesn't appear in Cmd+Tab or Mission Control
- `.floating` window level — stays above other windows
- Global hotkey to toggle (e.g., Cmd+Shift+S)
- Click outside to dismiss
- No dock icon (`LSUIElement = true`)
- SwiftUI view reading directly from SQLite
- Simpler than WidgetKit — no App Groups, no timeline refresh

### Option B: macOS Widget

WidgetKit widget in Notification Center:
- Scrollable MRU list
- Each row: tool icon, directory name, last ask (truncated), status badge, relative timestamp
- Tap → AppIntent that activates the session's terminal window
- Timeline refresh: every 30s or triggered by CLI

### Window Focusing (both options)

On tap/click, activate the session's terminal window:
1. Find the window by PID
2. Activate the parent app (Terminal/VS Code)
3. Bring that specific window to front
4. Implementation: AppleScript via `osascript`

## Open Questions

- [ ] Do we need a `name` or `label` field for user-assigned session names?
- [ ] Floating panel vs widget — decide after Phase 1 is working

## Tech Stack

- **Language**: Swift (shared across CLI and macOS app)
- **CLI framework**: swift-argument-parser
- **Database**: SQLite via GRDB (shared `SeshboardCore` package)
- **UI**: Swift/SwiftUI (Phase 2)
- **Window management**: AppleScript via `osascript`
