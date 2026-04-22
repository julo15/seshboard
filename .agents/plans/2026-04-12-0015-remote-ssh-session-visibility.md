# Plan: Remote SSH Session Visibility via `seshctl ssh` Wrapper

> **Revision 2** — rewritten based on feasibility, skeptic, and tech-plan reviews.
> Key changes: replaced PTY/OSC transport with reverse TCP port forward;
> dropped Linux cross-compilation from MVP scope; enumerated event schema;
> split Step 7 into smaller pieces; added PTY proxy integration tests.
> Reviews: `.agents/reviews/2026-04-12-0015-*-review-ssh-remote.md`

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run `swift build` (120s timeout) after each step; `make kill-build` on hang
- Run `make test` (30s timeout) after completing each major step
- If blocked, document the blocker here before stopping

## Overview
Allow seshctl on the user's Mac to see and focus sessions running on remote machines over SSH. A `seshctl-cli ssh <host>` wrapper command transparently injects an SSH reverse port forward (`-R`), listens for JSON session events tunneled back from the remote `seshctl-cli`, and writes them into the local SQLite database. Pressing Enter on a remote session row focuses the local terminal tab hosting the SSH connection.

## User Experience

### Setup (one-time, per remote host)
1. User installs `seshctl-cli` on the remote machine (manually — out of scope)
2. User registers Claude/Codex hooks on the remote pointing to `seshctl-cli` (same mechanism as local — out of scope)
3. No configuration needed on the local Mac beyond having `seshctl-cli` installed

### Daily use
1. User opens a terminal and types `seshctl-cli ssh user@remote-host` instead of `ssh user@remote-host`. All ssh flags and arguments pass through transparently (`seshctl-cli ssh -p 2222 user@host`, `seshctl-cli ssh host -- tmux attach`, etc.)
2. SSH session starts normally — the wrapper spawns `ssh` as a child process that directly owns the terminal. No PTY proxy, no byte interception, no visible difference to the user. Interactive programs (vim, less, top), SSH escape sequences (`~.`, `~C`), and terminal resize all work exactly as they do with plain `ssh`.
3. Inside the SSH session (with or without tmux), user starts a Claude session. Claude's hooks fire `seshctl-cli start` on the remote. The remote CLI writes to the remote DB as usual, AND attempts a TCP connection to `localhost:51337` (the well-known relay port). If the connection succeeds (because the wrapper's `-R` forward is active), it sends a JSON event and closes the connection. If it fails (not in a monitored session, or plain `ssh` was used), it silently moves on — zero overhead.
4. The wrapper accepts the TCP connection on the local side, reads the JSON event, and writes/updates a session row in the local SQLite DB.
5. User opens seshctl (menubar app). The remote session appears in the list with a hostname badge, showing the remote host, directory, branch, and tool.
6. User presses Enter on the remote session row. seshctl focuses the local terminal tab running the `seshctl-cli ssh` wrapper — the user lands right back in their SSH/tmux session, already looking at Claude.
7. When the SSH session ends (user types `exit`, connection drops, wrapper killed), all remote sessions associated with that wrapper are marked completed in the local DB.

### Edge cases visible to the user
- **Multiple wrappers to the same host**: the second wrapper's `-R 51337` bind will fail (port already taken on the remote). SSH still works but relay events only flow to the first wrapper. Documented limitation for MVP.
- **Plain `ssh` (not the wrapper)**: remote sessions are invisible to the local seshctl. The remote `seshctl-cli` still writes to the remote DB, so `seshctl-cli show` on the remote works. Silent, graceful degradation.
- **tmux on the remote**: works without any tmux configuration. The relay uses TCP (not the terminal byte stream), so tmux passthrough settings are irrelevant.
- **SSH `AllowTcpForwarding` disabled on server**: `-R` bind fails silently. SSH session works, relay events don't flow. Same as using plain `ssh`.

## Architecture

### Current architecture (local only)

```
Claude hook → seshctl-cli start/update/stop → writes to ~/...seshctl.sqlite
                                              ↓
                                    SeshctlApp reads via GRDB observation
                                              ↓
                                    Session appears in menubar panel
```

### New architecture (local + remote)

**Remote side (machine B):**
```
Claude hook → seshctl-cli start/update/stop
                ├── writes to remote ~/...seshctl.sqlite (unchanged)
                └── tries TCP connect to localhost:51337
                    ├── success → sends JSON event, closes connection
                    └── failure → no-op (not in a monitored SSH session)
```

**Local side (machine A):**
```
seshctl-cli ssh host
  ├── starts TCP listener on random local port P
  ├── spawns: ssh -R 51337:localhost:P <user-args>
  │     └── ssh directly owns the terminal (stdin/stdout/stderr)
  │         (no PTY proxy, no byte interception)
  └── accepts TCP connections on port P (tunneled from remote:51337)
        ├── reads JSON event
        ├── writes to local ~/...seshctl.sqlite
        │     with pid=wrapper PID, host_app=local terminal
        └── SeshctlApp sees session via GRDB observation
```

**Focus for remote sessions:** The local session row has `pid` set to the `ssh` child's PID. The existing `TerminalController.focus(pid)` walks the process tree from that PID, finds the local terminal app, and focuses the tab. No new focus code needed.

### Why reverse port forward (not PTY/OSC)

The original plan used OSC escape sequences in the terminal byte stream, requiring a full PTY proxy. Three independent reviews identified this as the wrong tradeoff:

| Concern | PTY/OSC | Reverse port forward |
|---|---|---|
| Raw terminal mode management | Required | Not needed (ssh owns terminal) |
| SIGWINCH forwarding | Required | Not needed (ssh handles it) |
| Byte-stream state machine | Required (handle split reads) | Not needed |
| tmux passthrough config | Required (`allow-passthrough on`) | Not needed (TCP, not terminal) |
| `/dev/tty` atomicity | POSIX doesn't guarantee for PTY | N/A |
| Signal handling complexity | High (self-pipe pattern) | Low (just wait for ssh child) |
| Interactive program compat | Must be verified (vim, less, etc.) | Automatic (ssh is unmodified) |
| New low-level concepts | ~6 | ~2 (TCP listener, child process) |

The user-facing UX is identical: `seshctl-cli ssh host`. Only the internal plumbing differs.

### Data flow in detail

**Emission (remote, per hook invocation):**
1. Hook fires `seshctl-cli update --status working --ask "..."` on remote
2. CLI writes to remote DB via `Database.updateSession()` (unchanged)
3. After the DB write, calls `SSHRelay.tryEmit(session:eventType:)`
4. `tryEmit` opens a TCP connection to `localhost:51337` with a 200ms connect timeout
5. If connection succeeds: serialize `RemoteSessionEvent` as JSON, write, close
6. If connection fails: return silently (not in a monitored SSH session, or port forward not active)

**Ingestion (local wrapper, event loop):**
1. Wrapper's TCP listener accepts a connection from the SSH tunnel
2. Reads JSON bytes until connection closes (remote sends one event per connection)
3. Parses `RemoteSessionEvent` from JSON
4. Calls `Database.ingestRemoteEvent(event:sshPid:hostAppBundleId:remoteHost:)`:
   - Looks up existing session by `remote_session_id == event.sessionId` AND `remote_host == remoteHost`
   - If found: updates mutable fields (directory, status, lastAsk, lastReply, gitBranch, updatedAt, etc.)
   - If not found: inserts new session with `pid = sshPid`, `hostAppBundleId = hostAppBundleId`
5. If event type is `stop`: marks the local session as completed

**Lifecycle:**
- **Wrapper startup**: detects local host app (process tree from wrapper PID, macOS only), parses ssh destination hostname from args, starts listener, spawns ssh child
- **Wrapper exit**: ssh child exits → wrapper marks all remote sessions with matching `remote_host` and `pid == sshPid` as completed → wrapper exits with ssh's exit code
- **SIGINT/SIGTERM**: wrapper ignores (ssh handles Ctrl-C); on ssh death, wrapper cleans up
- **Unexpected disconnect**: ssh exits with non-zero → same cleanup path
- **Reconnection**: new wrapper, new PID, new session rows. Old ones stay completed.

### Performance
- **Remote emission**: ~1ms per event (TCP connect + JSON write + close). Events fire ~20-50 times per Claude session. If relay port is not listening, connect fails in <1ms (connection refused, immediate).
- **Local ingestion**: ~1ms per event (JSON parse + GRDB write). Negligible.
- **Terminal overhead**: zero. ssh directly owns the terminal; the wrapper doesn't touch the byte stream.

## Current State

### seshctl-cli (Sources/seshctl-cli/)
- `SeshctlCLI.swift`: main entry point with `Start`, `Update`, `Stop`, `Show` subcommands
- `detectHostApp()` (line 91): walks process tree using macOS-only `proc_pidinfo` / `NSRunningApplication`
- Uses ArgumentParser for CLI structure

### SeshctlCore (Sources/SeshctlCore/)
- `Database.swift`: GRDB-based SQLite, migrations v1-v8, `startSession`/`updateSession`/`endSession`
- `Session.swift`: 20-field model, all Codable/GRDB-compatible

### SeshctlUI (Sources/SeshctlUI/)
- `TerminalController.swift`: focus/resume routing
- `SessionAction.swift`: canonical entry point for user actions

## Proposed Changes

### Strategy

**"Transparent relay" approach.** The wrapper injects `-R 51337:localhost:<local_port>` into the ssh command, spawns ssh as a child that directly owns the terminal, and runs a TCP listener for incoming relay events. The remote CLI tries `localhost:51337` after each DB write — if it connects, an event is relayed; if not, nothing happens. No PTY proxy, no terminal byte interception, no tmux configuration.

**Scope boundaries:**
- **In scope**: wrapper command, relay protocol, remote emission, local ingestion, schema, focus routing, tests
- **Out of scope**: Linux cross-compilation (MVP is macOS-to-macOS), remote binary installation, remote hook setup, UI redesign
- **Deferred**: Unix socket relay (avoids port conflicts), multi-wrapper-per-host support, Linux target for seshctl-cli

### Complexity Assessment

**Medium.** ~10 files touched/created, one new subsystem (TCP relay + child process management), one additive schema migration. No low-level PTY code, no byte-stream parsing, no signal handler complexity beyond waiting for a child process. The wrapper is conceptually a "launch ssh with extra flags + run a TCP server" — both are well-understood patterns in Swift. Regression risk is low: existing sessions, focus routing, and DB logic are unchanged. The relay emission on the remote side is a fire-and-forget TCP write with a timeout guard.

Tricky parts:
1. **SSH arg parsing** for extracting the destination hostname — SSH args are complex. Mitigated by using `ssh -G` to resolve config.
2. **Child process lifecycle** — wrapper must not exit before ssh, must forward exit code, must clean up sessions on exit.
3. **Concurrent DB access** — wrapper and SeshctlApp both write to the same SQLite DB. GRDB's WAL mode handles this, but write contention needs a retry policy.

## Impact Analysis

- **New Files**:
  - `Sources/SeshctlCore/SSHRelay.swift` — `RemoteSessionEvent` model, JSON encode/decode, `tryEmit()` (TCP relay to localhost:51337)
  - `Sources/seshctl-cli/SSHCommand.swift` — `SSH` subcommand (TCP listener, ssh child management, event ingestion loop)
  - `Tests/SeshctlCoreTests/SSHRelayTests.swift` — encode/decode tests, tryEmit tests with mock server
  - `Tests/SeshctlCoreTests/SSHCommandTests.swift` — wrapper lifecycle tests

- **Modified Files**:
  - `Sources/SeshctlCore/Database.swift` — migration v9 (remote_host, remote_session_id), `ingestRemoteEvent()` method, `markRemoteSessionsCompleted(sshPid:remoteHost:)` method
  - `Sources/SeshctlCore/Session.swift` — add `remoteHost: String?`, `remoteSessionId: String?`
  - `Sources/seshctl-cli/SeshctlCLI.swift` — register `SSH` subcommand, call `SSHRelay.tryEmit()` after DB writes in Start/Update/Stop
  - Test files with `Session(...)` literals — add `remoteHost: nil, remoteSessionId: nil`

- **Dependencies**:
  - `Network` framework (NWListener for TCP server) — macOS 10.14+, already within our macOS 13 minimum
  - `Foundation` (JSONEncoder/Decoder, Process) — already used

- **Similar Modules**:
  - `Database.startSession()` / `updateSession()` — `ingestRemoteEvent()` reuses the same DB write patterns
  - `detectHostApp()` process tree walk — reused in wrapper for local host app detection

## Key Decisions

1. **Well-known relay port 51337**: remote CLI always tries `localhost:51337`. Simple, no discovery protocol. Limitation: one active relay per remote host. Acceptable for MVP.
2. **TCP per-event connections (not persistent)**: each event opens a new TCP connection, sends JSON, closes. Simple, stateless, no keepalive/heartbeat. Overhead is negligible for the ~20-50 events per Claude session.
3. **ssh directly owns the terminal**: the wrapper spawns ssh via `Process()` with inherited stdin/stdout/stderr. No PTY proxy, no byte interception. ssh handles terminal resize, escape sequences, interactive programs, Ctrl-C — everything works identically to plain `ssh`.
4. **200ms connect timeout for relay**: keeps hook latency low. If the relay isn't listening, the connect fails in <1ms (ECONNREFUSED). The timeout is a safety net for network issues.
5. **macOS-to-macOS for MVP**: defer Linux cross-compilation. GRDB doesn't support Linux (confirmed by maintainer, issue #796), so a Linux target would need a separate thin binary without DB support. Significant scope; deferred.
6. **`ssh -G` for hostname resolution**: the wrapper runs `ssh -G <args>` to extract the resolved `Hostname` from SSH config. This handles Host aliases, ProxyCommand, jump hosts — all SSH config complexity resolved by ssh itself.
7. **Wrapper PID vs ssh child PID**: we use the ssh child PID as the session's `pid` for focus routing. The existing process tree walk from the ssh child PID → finds the local terminal app → focuses the tab.

## RemoteSessionEvent Schema

The JSON event sent over the relay. Explicitly enumerated per tech-plan review feedback.

```swift
struct RemoteSessionEvent: Codable {
    let type: EventType               // "start", "update", "stop"
    let sessionId: String             // remote session's UUID (becomes remoteSessionId locally)

    // Session fields — included
    let conversationId: String?
    let tool: String                  // "claude", "gemini", "codex"
    let directory: String
    let launchDirectory: String?
    let lastAsk: String?
    let lastReply: String?
    let status: String                // "idle", "working", "waiting", "completed", "canceled"
    let gitRepoName: String?
    let gitBranch: String?
    let startedAt: Date
    let updatedAt: Date

    enum EventType: String, Codable {
        case start, update, stop
    }
}

// Excluded fields (local-only, set by the wrapper):
// - id (local session gets its own UUID)
// - pid (set to ssh child PID by wrapper)
// - hostAppBundleId (detected from wrapper's local process tree)
// - hostAppName (detected locally)
// - windowId (local terminal window)
// - transcriptPath (local file path, not accessible remotely)
// - launchArgs (local hook args)
// - lastReadAt (local UI state)
// - remoteHost (set by wrapper from ssh args)
// - remoteSessionId (set from event.sessionId by wrapper)
```

## Implementation Steps

### Step 1: Schema + model changes for remote sessions
- [ ] Add migration `v9_add_remote_fields` in `Sources/SeshctlCore/Database.swift`: add nullable `remote_host TEXT` and `remote_session_id TEXT` columns
- [ ] Add `remoteHost: String?` and `remoteSessionId: String?` to `Sources/SeshctlCore/Session.swift` with coding keys `remote_host`, `remote_session_id`
- [ ] Add `Database.ingestRemoteEvent(event:sshPid:hostAppBundleId:remoteHost:)` — looks up by `remote_session_id + remote_host`, upserts
- [ ] Add `Database.markRemoteSessionsCompleted(sshPid:remoteHost:)` — marks all active sessions with matching pid + remote_host as completed
- [ ] Update all `Session(...)` struct literals in tests to include `remoteHost: nil, remoteSessionId: nil`

### Step 2: SSHRelay protocol (encode/decode + emit)
- [ ] Create `Sources/SeshctlCore/SSHRelay.swift`
- [ ] Define `RemoteSessionEvent` struct (as specified in the schema section above)
- [ ] Implement `SSHRelay.tryEmit(session:eventType:)`:
  - Opens TCP socket to `localhost:51337` with 200ms connect timeout
  - Encodes `RemoteSessionEvent` as JSON
  - Writes JSON bytes, closes socket
  - On any error: returns silently (never throws, never blocks)
- [ ] Implement `SSHRelay.decode(data: Data) -> RemoteSessionEvent?` for the ingestion side

### Step 3: Add relay emission to CLI commands
- [ ] In `Sources/seshctl-cli/SeshctlCLI.swift`, after `db.startSession()` in `Start`, call `SSHRelay.tryEmit(session: session, eventType: .start)`
- [ ] After `db.updateSession()` in `Update`, call `SSHRelay.tryEmit(session: session, eventType: .update)`
- [ ] After `db.endSession()` in `Stop`, call `SSHRelay.tryEmit(session: session, eventType: .stop)` (need to fetch session before ending it to have the fields)
- [ ] Ensure emission failures are silently swallowed — no impact on hook execution

### Step 4: SSH hostname resolution
- [ ] In `Sources/seshctl-cli/SSHCommand.swift`, implement `resolveHostname(sshArgs: [String]) -> String?`
- [ ] Runs `ssh -G <args>` as a subprocess, parses stdout for `^hostname (.+)$` (case-insensitive)
- [ ] Falls back to naive arg parsing if `ssh -G` fails: take the last positional argument (skip flags that consume a value: `-i`, `-L`, `-R`, `-D`, `-b`, `-c`, `-l`, `-m`, `-O`, `-S`, `-W`, `-w`, `-J`, `-F`, `-o`, `-p`), split `user@host` on `@`
- [ ] Add unit tests for the fallback parser with common arg patterns

### Step 5: SSH wrapper command (TCP listener + ssh child)
- [ ] Create `Sources/seshctl-cli/SSHCommand.swift` `SSH` subcommand registered via ArgumentParser
- [ ] Accept remaining arguments: `@Argument(parsing: .allUnrecognized) var sshArgs: [String]`
- [ ] On `run()`:
  1. Start `NWListener` on `localhost`, random port (let the OS assign)
  2. Resolve hostname via `resolveHostname(sshArgs:)`
  3. Detect local host app via existing `detectHostApp()` (for `hostAppBundleId`)
  4. Spawn ssh child via `Process`: `ssh -R 51337:localhost:<local_port> <sshArgs...>`
     - Inherit stdin/stdout/stderr (ssh directly owns the terminal)
  5. Set `Process.terminationHandler`: on ssh exit, call `Database.markRemoteSessionsCompleted(sshPid:remoteHost:)`, then `Foundation.exit(process.terminationStatus)`
  6. NWListener connection handler: on accept, read all data, call `SSHRelay.decode()`, call `Database.ingestRemoteEvent()`
  7. Install SIGINT/SIGTERM handlers that do nothing (let ssh handle Ctrl-C; wrapper waits for ssh to exit)
  8. `RunLoop.main.run()` to keep the process alive

### Step 6: Write tests
- [ ] `Tests/SeshctlCoreTests/SSHRelayTests.swift`:
  - [ ] Test `RemoteSessionEvent` JSON encode/decode round-trip for start, update, stop
  - [ ] Test decode rejects invalid JSON, missing required fields
  - [ ] Test `tryEmit` succeeds when a test TCP server is listening on 51337
  - [ ] Test `tryEmit` returns silently when nothing is listening (no throw, no hang)
  - [ ] Test `tryEmit` returns within 300ms even if connection hangs (timeout guard)
- [ ] `Tests/SeshctlCoreTests/DatabaseTests.swift`:
  - [ ] Test `ingestRemoteEvent` creates a new session with correct remote fields
  - [ ] Test `ingestRemoteEvent` updates existing session matched by `remote_session_id + remote_host`
  - [ ] Test `ingestRemoteEvent` does not update local sessions (no remote_session_id match)
  - [ ] Test `markRemoteSessionsCompleted` marks only matching sessions
- [ ] `Tests/SeshctlCoreTests/SSHCommandTests.swift`:
  - [ ] Test `resolveHostname` with common arg patterns: `host`, `user@host`, `-p 2222 host`, `-i key host`, `-J bastion host`
  - [ ] Test `resolveHostname` with Host alias (mock `ssh -G` output)
  - [ ] Test wrapper lifecycle: spawn wrapper around a short-lived `echo hello && exit`, verify sessions are marked completed on exit
- [ ] Update all `Session(...)` struct literals in existing tests for new fields
- [ ] Run full test suite: `make test`

## Acceptance Criteria

- [ ] [test] `RemoteSessionEvent` JSON encode/decode round-trip
- [ ] [test] `tryEmit` succeeds with a listening server and fails silently without one
- [ ] [test] `ingestRemoteEvent` creates and updates remote sessions in local DB
- [ ] [test] `markRemoteSessionsCompleted` marks sessions completed on wrapper exit
- [ ] [test] `resolveHostname` correctly extracts hostname from various SSH arg patterns
- [ ] [test] All existing tests still pass (no regressions)
- [ ] [test-manual] `seshctl-cli ssh host` connects to a remote host and starts an interactive shell
- [ ] [test-manual] Starting a Claude session on the remote causes a row to appear in local seshctl within seconds
- [ ] [test-manual] Session status updates (working/idle/waiting) propagate to local seshctl
- [ ] [test-manual] Pressing Enter on a remote session row focuses the local terminal tab running `seshctl-cli ssh`
- [ ] [test-manual] Ending the SSH session marks remote sessions as completed
- [ ] [test-manual] Works through tmux on the remote (no special tmux config needed)
- [ ] [test-manual] Interactive programs (vim, less, top) work normally through the wrapper
- [ ] [test-manual] SSH escape sequences (`~.`, `~C`) work normally
- [ ] [test-manual] Terminal resize works correctly
- [ ] [test-manual] `seshctl-cli` builds on macOS after all changes

## Edge Cases

- **Multiple wrappers to the same remote host**: second wrapper's `-R 51337` bind fails. SSH session works, relay events flow to the first wrapper only. Documented MVP limitation. Future fix: use per-session port or Unix socket.
- **SSH ControlMaster multiplexing**: if ControlMaster is active, the wrapper's ssh child may reuse an existing connection. The `-R` forward is only set up on the master connection, so subsequent wrappers can't relay. Same limitation as multi-wrapper. Workaround: `seshctl-cli ssh -o ControlMaster=no host`.
- **Something else listening on remote port 51337**: the remote CLI sends JSON to an unrelated service. The JSON is a harmless, self-describing document. The listener will either ignore it or close the connection. No data corruption risk.
- **SSH connection drops mid-session**: ssh exits with non-zero, wrapper's termination handler marks sessions completed. If wrapper is killed with SIGKILL (no cleanup), sessions become stale — existing stale session detection logic handles this.
- **Remote seshctl-cli is older version (no relay emission)**: remote CLI doesn't call `tryEmit`, nothing connects to the relay port. Wrapper is just a slightly fancier `ssh`. Graceful degradation.
- **Rapid hook fires (concurrent relay emissions)**: each emission opens a separate TCP connection. NWListener handles concurrent connections naturally. GRDB WAL mode handles concurrent writes; if contention occurs, GRDB retries automatically (default busy timeout).
- **Large JSON events**: Session events are ~800 bytes of JSON. Well within TCP buffer sizes. Single read/write per connection.
- **Wrapper exit code**: wrapper exits with ssh's exit code so that `$?` and calling scripts see the correct status.
