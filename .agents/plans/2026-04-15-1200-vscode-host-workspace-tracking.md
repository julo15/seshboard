# Fix: VS Code focus opens new window when terminal cwd differs from host workspace

**Created:** 2026-04-15
**Status:** Proposed

## Problem

When a session's terminal was opened in one VS Code window (workspace = folder1) and then the shell `cd`'d into an unrelated folder (folder2) before the LLM session started, seshctl's focus flow opens a **new** VS Code window on folder2 instead of raising the existing folder1 window that actually hosts the live terminal.

Reproduction:
1. Open VS Code on folder1.
2. Open an integrated terminal (cwd = folder1).
3. `cd ../folder2`.
4. Run `claude` (or another supported LLM). Hook fires `seshctl-cli start` with `dir = folder2`.
5. In seshboard, press Enter on the active session.
6. **Observed:** VS Code opens a new window for folder2. Terminal in folder1 window is never focused.
7. **Expected:** The existing folder1 window comes forward and the terminal is revealed.

## Root cause

`TerminalController.focusVSCode` (`Sources/SeshctlUI/TerminalController.swift:527`) calls:

```swift
env.runShellCommand("/usr/bin/open", args: ["-b", bundleId, directory])
```

It passes the session's `launchDirectory` (captured at `seshctl-cli start` time from the shell's cwd — folder2 in this scenario) to `open -b`. VS Code's `open` behavior is "open this folder as a workspace," which spawns a new window when that folder isn't already an open workspace.

The `focus-terminal?pid=<pid>` URI that fires next is then routed to the frontmost window's extension host — which is now the brand-new folder2 window, where the target PID isn't registered. The terminal is never raised.

The prior fix (commit `8cc8b94`, v8 migration adding `launch_directory`) handled the case where the shell `cd`'d to a **subfolder** of the hosting workspace (e.g. a worktree under folder1) — in that case `launchDirectory` still matched an open workspace. It doesn't help when the cwd is outside the hosting workspace entirely.

## Design: track the hosting VS Code window at terminal creation time

The hosting window is a stable property of a terminal — VS Code doesn't allow moving terminals between windows, and shell `cd` doesn't change which window the terminal lives in. So the companion extension can capture this mapping eagerly when each terminal opens, and the CLI can look it up synchronously at session-start time.

### Extension side (`vscode-extension/src/extension.ts`)

1. On `onDidOpenTerminal`:
   - Resolve `terminal.processId` (the shell PID).
   - Resolve hosting workspace folders: record **all** `vscode.workspace.workspaceFolders` as an array of `fsPath` strings. If no workspace is open, record an empty array (no-folder window).
   - Resolve the shell's start time (seconds since epoch) via `ps -o lstart= -p <pid>` or by parsing `/proc`-equivalent on macOS (`proc_bsdinfo.pbi_start_tvsec` via a small helper shelling out to `ps -o start=`). This is used on the read side to defeat PID recycling.
   - Write `{shellPid, startTime, workspaceFolders: string[]}` to `~/.local/share/seshctl/vscode-windows/<pid>.json` using atomic write (`<pid>.json.tmp` → `rename()`).
2. On `onDidCloseTerminal`:
   - Remove the entry for that shell PID.
3. On `activate`:
   - Backfill entries for `vscode.window.terminals` already open (handles `Developer: Reload Window`).
   - Sweep stale entries whose PIDs no longer exist OR whose recorded `startTime` no longer matches the live PID's startTime (defeats PID recycling).
4. Concurrency: per-pid files eliminate multi-writer races. Atomic rename handles the reader-mid-write case.

### CLI side (`Sources/seshctl-cli/SeshctlCLI.swift`)

In `StartCommand.run`, before calling `db.startSession`:

1. Walk the parent-PID chain starting from `pid` (the shell PID passed in by the hook), up to 10 hops.
2. For each PID in the chain, check whether `~/.local/share/seshctl/vscode-windows/<pid>.json` exists.
3. When a file exists, read it and verify the recorded `startTime` matches the live PID's startTime (defeats PID recycling). If mismatched, treat as stale and continue walking.
4. First valid hit wins: read `workspaceFolders[0]` and pass it as a new `hostWorkspaceFolder` argument to `startSession`. (First folder suffices — for multi-root, `open -b <anyMemberFolder>` raises the window and the PID-match URI handler routes into the correct terminal.)
5. If no valid hit, `hostWorkspaceFolder = nil` (today's behavior preserved).

### Database (`Sources/SeshctlCore/Database.swift`, `Session.swift`)

1. Migration `v9_add_host_workspace_folder`: add nullable TEXT column `host_workspace_folder` to `sessions`. No backfill (old rows remain `NULL`; focus path falls back to `launchDirectory`).
2. Add `hostWorkspaceFolder: String?` to `Session` struct and `CodingKeys`.
3. Thread through `startSession` signature and the insert SQL.

### Focus path (`Sources/SeshctlUI/TerminalController.swift`, `SessionAction.swift`)

1. `SessionAction.focusActiveSession` resolves the directory to pass to `focus()` with this precedence:
   - `session.hostWorkspaceFolder` (new, most reliable)
   - `session.launchDirectory` (existing fallback)
   - `session.directory` (ultimate fallback)
2. `TerminalController.focus` gains a `hostWorkspaceFolder: String?` parameter and forwards it to `focusVSCode`.
3. `focusVSCode` uses `hostWorkspaceFolder` (if non-nil) in the `open -b bundleId <dir>` call. If the extension recorded `null` (no-folder window), skip the directory argument entirely — just `open -b bundleId` to activate the app, then let the URI handler do its work.

## What this does NOT change

- No IPC at session-start time. The CLI does a file-existence check and a small JSON read — microseconds, not milliseconds.
- No change to the `focus-terminal?pid=` URI protocol or the extension's URI handler.
- No change to AppleScript-based terminal flows (Terminal.app, iTerm2, Ghostty, Warp).
- Resume path (inactive sessions) is unchanged — it correctly targets the session's directory since there's no live terminal to follow.

## Edge cases & fallbacks

| Case | Behavior |
|---|---|
| Extension not installed | Map file never exists → `hostWorkspaceFolder = nil` → current behavior (uses `launchDirectory`). |
| Extension installed but not yet activated when terminal opens | `onStartupFinished` activation plus backfill on `activate()` covers this for existing terminals. New terminals opened before activation: lost, but this is a ~1s window after VS Code launch. |
| Multiple windows, same workspace folder | Map records the folder only. `open -b bundleId <dir>` focuses whichever window is frontmost among those showing that folder. Acceptable — there's no way to distinguish them externally, and the URI handler's PID match will route into the right one. |
| Cursor / VS Code Insiders | Same extension logic applies. The companion extension is distributed per-fork; each fork's extension writes to the same map. Entries are keyed by PID so no collision. |
| Remote / SSH windows | The extension runs in the remote host — its PID view is remote, not local. The CLI walks local PIDs. Map file is local, so remote terminals simply never get recorded → falls back to `launchDirectory`. Acceptable for v1. |
| Stale entries (extension crashed) | Sweep on activation; also the CLI could skip entries older than N days. Low priority — per-pid files + PID recycling means at worst we target a wrong directory once, which falls back harmlessly to "open that folder." |
| Workspace changes (`code -a`, add folder to workspace) | The hosting window changes `workspaceFolders[0]` semantics. We could listen to `onDidChangeWorkspaceFolders` and update the map; v1 can ignore this (rare flow). |
| Stale workspace (user closed the window but detached shell kept running) | `open -b <dir>` spawns a new window on that folder — still better than opening on cwd. Document, don't fix. |
| PID recycling (stale pid file collides with new unrelated shell) | `startTime` check on read rejects the stale file; CLI continues pid-chain walk. |
| `Developer: Reload Window` | Terminals survive reload; `onDidOpenTerminal` does not re-fire. Backfill on `activate()` restores the map. Manual smoke test must cover this. |

## Tests

- `DatabaseTests`: v9 migration applies cleanly; new column nullable; round-trip on `Session`.
- `SessionActionTests`: focus path prefers `hostWorkspaceFolder` > `launchDirectory` > `directory`.
- `TerminalControllerTests`: `focusVSCode` called with `hostWorkspaceFolder = nil` omits the directory arg; with a value uses it. Also: provided path that doesn't exist on disk is still passed through (VS Code handles missing paths).
- CLI: new unit for "walk pid chain, find map entry" — use a fake filesystem directory under a tmpdir, overridden via `SESHCTL_VSCODE_WINDOWS_DIR`. Cover: depth limit, pid==1 termination, self-loop guard, startTime mismatch rejected.
- Extension: manual smoke test — open VS Code on folder A, open terminal, verify `~/.local/share/seshctl/vscode-windows/<pid>.json` appears with the workspace path. Close terminal, verify file removed. Repeat after `Developer: Reload Window` — verify backfill restores the map.

## Rollout

1. Ship CLI + DB migration + focus path with the fallback logic.
2. Ship extension update in the same release.
3. Users on old extensions continue to work via the `launchDirectory` fallback.
4. No data migration required.

## Open questions

- Should the map location be configurable via env var for testing? (Yes — default to `~/.local/share/seshctl/vscode-windows/`, override via `SESHCTL_VSCODE_WINDOWS_DIR`.)
- Do we also want to record the VS Code window's native window ID (via some future API) for tighter focusing? Not yet available in stable VS Code API as of this writing — out of scope.
