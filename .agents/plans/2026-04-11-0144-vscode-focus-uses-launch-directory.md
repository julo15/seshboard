# Plan: VS Code focus should target the original session window, not the current cwd

## Working Protocol
- Use parallel subagents for independent reads across Sources and Tests
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- After each code step, run `swift build` with a 120s timeout (run `make kill-build` on any hang)
- Run `make test` (30s timeout) after implementation is complete, not per step
- If blocked, document the blocker here before stopping

## Overview
Fix a bug where pressing Enter on an active VS Code session whose shell has `cd`'d into a worktree opens a new VS Code window on the worktree folder instead of focusing the existing terminal in the original window. Track the launch directory at session start and use it (not the live cwd) when activating VS Code for focus.

## User Experience

Primary flow (the reported bug):
1. User runs `claude` inside VS Code with folder `~/Documents/me/qbk-scheduler` open. Seshctl records an active session.
2. User asks Claude to create a worktree at `~/Documents/me/qbk-scheduler.worktrees/court-day-view`. Claude `cd`s into it. Seshctl's hook fires `seshctl-cli update --dir <worktree>` so the row now displays the worktree path and branch — the VS Code window itself is still the original one hosting the live terminal.
3. User opens seshctl and presses Enter on that active session row.
4. **Expected:** VS Code comes forward to the original `qbk-scheduler` window and the terminal tab running Claude is selected.
5. **Current (buggy):** VS Code opens a new window on the worktree folder and nothing is focused. The original terminal is orphaned behind the new window.

Secondary flow (resume unchanged): when the session is inactive (no live process), pressing Enter still resumes via `resumeInVSCode`, which passes the current (worktree) cwd to `open -b`. The user confirmed this is acceptable — if the terminal isn't alive, opening the worktree folder is fine.

## Architecture

**Runtime today.** When seshctl's `focusActiveSession` runs for a VS Code session (SessionAction.swift:46), it calls `TerminalController.focus(pid:directory:bundleId:windowId:)` with `session.directory`. For VS Code, that funnels into `focusVSCode(pid:directory:bundleId:)` (TerminalController.swift:473), which runs:

1. `open -b <bundleId> <directory>` — because `directory` is passed as a positional arg to `open -b`, macOS asks VS Code to open that folder. VS Code's behavior: if a window is already open on that folder, focus it; otherwise open a new window. In the bug, the worktree folder is *not* yet open, so VS Code spawns a new window — and that new window becomes the frontmost extension host.
2. `open vscode://julo15.seshctl/focus-terminal?pid=<pid>` — the URI is delivered to the currently-frontmost VS Code window's extension host. The handler (vscode-extension/src/extension.ts:14) searches `vscode.window.terminals` by PID (direct match, then process-tree ancestry). Each window has its own extension host and can only see its own terminals, so the handler in the *new* window never sees the terminal that lives in the *original* window. Result: silent miss, no tab focused.

**Why the PID column points at the worktree.** The `start` subcommand captures `FileManager.default.currentDirectoryPath` into `sessions.directory` (Database.swift:156). Claude's PreToolUse hook fires `seshctl-cli update --dir <new_cwd>` after each `cd`, which overwrites that column (Database.swift:221). Seshctl has no column that preserves the original folder VS Code was launched against.

**Runtime after this change.** Add a new non-null column `launch_directory` that is set at `start` and *never* updated. `focusVSCode` uses `session.launchDirectory` (not `session.directory`) for the `open -b` call. Because the original VS Code window is already open on that folder, `open -b <bundleId> <launchDirectory>` focuses the existing window instead of opening a new one; the URI handler then runs in the correct extension host and finds the terminal by PID. The session row's displayed folder/branch (which reads from `directory`) is unchanged — it keeps showing the current worktree, which matches user intent.

`resumeInVSCode` keeps using `session.directory` (the worktree) — the user wants inactive resumes to land in the current working directory, not the launch directory.

## Current State

- `Sources/SeshctlCore/Database.swift`:
  - `migrate()` has migrations v1–v7 (Database.swift:32). v1 defines `directory` as NOT NULL (line 40); no `launch_directory` column exists.
  - `startSession(...)` writes `directory: directory` (line 156).
  - `updateSession(...)` overwrites `session.directory` from `update --dir` (line 221).
- `Sources/SeshctlCore/Session.swift` — `Session` model; will gain `launchDirectory`.
- `Sources/seshctl-cli/SeshctlCLI.swift`:
  - `start` subcommand gathers cwd and calls `startSession` (passes `FileManager.default.currentDirectoryPath` as `directory`).
  - `update` subcommand reads `--dir` and calls the DB update path.
- `Sources/SeshctlUI/TerminalController.swift`:
  - `focus(pid:directory:bundleId:windowId:)` at line ~120 dispatches to `focusVSCode` (line 126) for VS Code / Cursor / VSCode Insiders.
  - `focusVSCode(pid:directory:bundleId:)` at line 473: `open -b bundleId directory` then the `focus-terminal?pid=` URI.
  - `resumeInVSCode(command:directory:bundleId:)` at line 483: also uses `open -b bundleId directory`. Unchanged by this plan.
- `Sources/SeshctlUI/SessionAction.swift`:
  - `focusActiveSession` (line 46) calls `TerminalController.focus(pid: session.pid, directory: session.directory, ...)`. Needs to pass `launchDirectory` instead for focus (but the plumbing should stay inside the controller — see Proposed Changes).
- `Tests/SeshctlUITests/TerminalControllerTests.swift`:
  - `vscodeRouting` (line 400), `cursorRouting` (line 415) assert the current buggy `open -b bundleId directory` behavior. Both must be updated.

## Proposed Changes

**Strategy.** Add one column (`launch_directory`) rather than trying to detect which window hosts which terminal at focus time. The launch directory is the only piece of data we can reliably capture and it's sufficient for VS Code's "open or focus" behavior.

Concretely:

1. **Schema:** New migration `v8_add_launch_directory`. Column is `TEXT` and nullable at the SQL level (to allow backfilling existing rows). In the migration, backfill `launch_directory = directory` for existing rows so pre-migration sessions keep working — the old launch directory is unknowable, so using the current `directory` is the best fallback.
2. **Model:** `Session` gains `launchDirectory: String?`. Treat it as optional in Swift; call sites default to `launchDirectory ?? directory`.
3. **CLI `start`:** Pass the same cwd into both `directory` and `launch_directory`. `launch_directory` is written once and never updated.
4. **CLI `update --dir`:** Only updates `directory`, never `launch_directory`. No code change needed if we simply don't reference the new column in the update path.
5. **Focus routing:** `TerminalController.focus(...)` grows a new optional `launchDirectory` parameter. `SessionAction.focusActiveSession` passes `session.launchDirectory`. Inside the controller, the VS Code branch uses `launchDirectory ?? directory` for the `open -b` call. All other terminal apps ignore the new parameter.
6. **Resume:** No change. `resumeInVSCode` keeps using `session.directory`.

**Why not other options:**
- *Drop the directory arg entirely from `focus`.* Fails when VS Code's last-focused window isn't the one hosting the terminal — `open -b` without a folder brings up whichever window was most recently active, and the URI handler may land in the wrong extension host.
- *Match by TTY in the extension.* Cleaner long-term but requires rebuilding and republishing the companion extension, plus handling the case where multiple windows all see the same TTY. Out of scope here.
- *Detect window/workspace ID via the extension.* Would need a new round-trip at session start to record which VS Code window hosts the terminal. Much bigger surface for a bug with a clean local fix.

### Complexity Assessment

**Low.** ~5 files touched, one schema migration following the same pattern as v2–v7, one new optional parameter threaded from `SessionAction` through `TerminalController.focus` into `focusVSCode`. No new patterns, no cross-cutting concerns. Regression risk is isolated to the VS Code focus path; Terminal/iTerm/Ghostty focus are unaffected because they ignore the new field. The migration backfills existing rows from `directory`, so upgrade is safe.

## Impact Analysis

- **New Files:** none.
- **Modified Files:**
  - `Sources/SeshctlCore/Database.swift` — add migration v8, write `launch_directory` in `startSession`.
  - `Sources/SeshctlCore/Session.swift` — add `launchDirectory` stored property and codable mapping.
  - `Sources/seshctl-cli/SeshctlCLI.swift` — pass cwd to both fields in `start`; make sure `show` prints launch dir if useful for debugging (optional).
  - `Sources/SeshctlUI/TerminalController.swift` — new `launchDirectory` param on `focus(...)`; `focusVSCode` uses `launchDirectory ?? directory`.
  - `Sources/SeshctlUI/SessionAction.swift` — pass `session.launchDirectory` into `TerminalController.focus`.
  - `Tests/SeshctlUITests/TerminalControllerTests.swift` — update `vscodeRouting` and `cursorRouting`, add a new test for the launch-vs-current-dir case.
  - Possibly `Tests/SeshctlCoreTests/DatabaseTests.swift` (if it exists) — assert migration backfill and start/update semantics.
- **Dependencies:**
  - Depends on the existing GRDB `DatabaseMigrator` migration chain.
  - Depends on `SessionAction` being the sole entry point (enforced by `AGENTS.md`) — any new caller of focus must also thread `launchDirectory`.
- **Similar Modules / Reuse:** The existing v2–v7 `ALTER TABLE` migrations are the template for v8 — same shape, one `t.add(column:)` call plus a backfill `UPDATE`. No new abstraction required.

## Key Decisions

- **Nullable vs non-null column:** nullable in SQL so the migration can backfill cleanly. In Swift, treat as `String?` and fall back to `directory` at call sites. Future `start` calls always populate it, but we never crash on pre-migration rows.
- **Only VS Code uses it:** `launchDirectory` is plumbed through `focus` generically but only consumed by `focusVSCode`. This avoids special-casing on the call site while keeping Terminal.app / iTerm / Ghostty unchanged.
- **Resume stays on `directory`:** per user direction — if the terminal isn't alive, opening the worktree folder is the right behavior.

## Implementation Steps

### Step 1: Schema migration + model
- [x] Add migration `v8_add_launch_directory` in `Sources/SeshctlCore/Database.swift` that adds a nullable `launch_directory TEXT` column and runs `UPDATE sessions SET launch_directory = directory WHERE launch_directory IS NULL`
- [x] Add `launchDirectory: String?` to `Sources/SeshctlCore/Session.swift` with codable/column mapping matching the other optional string fields (e.g. `transcript_path`)
- [x] In `startSession(...)` (`Database.swift:128`), accept a `launchDirectory: String? = nil` parameter and write it into the row (defaulting to `directory` when nil so old call sites still work)

### Step 2: CLI writes launch directory at start
- [x] In `Sources/seshctl-cli/SeshctlCLI.swift` `start` subcommand, pass `FileManager.default.currentDirectoryPath` to both `directory` and `launchDirectory` on the `startSession` call
- [x] Verify `update --dir` code path does NOT touch `launch_directory` (no change should be needed; confirm by reading Database.swift:220-225)

### Step 3: Focus threads launch directory to VS Code branch
- [x] Add an optional `launchDirectory: String?` parameter to `TerminalController.focus(pid:directory:bundleId:windowId:environment:)` in `Sources/SeshctlUI/TerminalController.swift`
- [x] In the VS Code branch inside `focus(...)`, pass `launchDirectory ?? directory` into `focusVSCode(pid:directory:bundleId:env:)`
- [x] Leave `focusVSCode` body using its `directory` param — the caller now supplies the launch directory for it
- [x] In `Sources/SeshctlUI/SessionAction.swift` `focusActiveSession` (line 46), pass `session.launchDirectory` into `TerminalController.focus(...)`

### Step 4: Write tests
- [x] Update `Tests/SeshctlUITests/TerminalControllerTests.swift::vscodeRouting` to call `focus` with `launchDirectory: "/tmp/launch"` and `directory: "/tmp/worktree"`, and assert `open -b com.microsoft.VSCode /tmp/launch` was executed (not `/tmp/worktree`)
- [x] Update `cursorRouting` similarly for the Cursor bundle
- [x] Add a new test `vscodeFocusFallsBackToDirectoryWhenLaunchDirMissing`: call `focus` with `launchDirectory: nil, directory: "/tmp/project"`, assert `open -b com.microsoft.VSCode /tmp/project`
- [x] Add a new test asserting `focusVSCode` does NOT open a second `open -b` with the worktree path (guards against regression)
- [x] If `Tests/SeshctlCoreTests/DatabaseTests.swift` exists: add a test that calling `startSession(directory:...)` without an explicit `launchDirectory` stores the same value in both columns, and that `update --dir` style mutations don't change `launch_directory`
- [x] Run `make test` (30s timeout) from a subagent and confirm green

## Acceptance Criteria
- [x] [test] `TerminalControllerTests.vscodeRouting` asserts `open -b com.microsoft.VSCode <launchDirectory>` (not the worktree)
- [x] [test] `TerminalControllerTests.cursorRouting` asserts `open -b com.todesktop.230313mzl4w4u92 <launchDirectory>`
- [x] [test] New VS Code test covers the `launchDirectory == nil` fallback (uses `directory`)
- [x] [test] `startSession` persists `launch_directory` equal to `directory` when not explicitly set; `update --dir` leaves `launch_directory` unchanged
- [ ] [test-manual] Reproduce the original bug: start a Claude session in VS Code, `cd` into a worktree subfolder, open seshctl, Enter on the active session → original window is raised and the terminal tab is focused; no new window is created
- [ ] [test-manual] Active session focus for Terminal.app / iTerm2 / Ghostty still works (regression check)
- [ ] [test-manual] Inactive session resume still opens the current (worktree) folder as a new VS Code window — unchanged behavior

## Edge Cases
- **Pre-migration sessions:** backfilled so `launch_directory = directory`. Focus behavior matches current behavior for those rows. Acceptable.
- **User deletes the original VS Code window before pressing Enter:** `open -b <bundle> <launchDir>` opens a new window on the launch directory. URI handler won't find the terminal (it's dead). User sees a window on the original folder — the session should probably have transitioned to inactive by then anyway; if it hasn't, this is the same failure mode as today.
- **Launch directory no longer exists on disk:** VS Code handles missing folders by showing an error toast; we don't need to defend against this specifically.
- **Multiple active sessions from the same launch directory:** `open -b` focuses that window, URI handler matches by PID, so each session still resolves to its own terminal tab.
