# Plan: Remote Peer Session Visibility (SSH-exec, on-demand)

> **Superseded (2026-04-20)**: Not shipping. After revisiting seshctl's Finder-for-Claude-sessions scope, SSH peer sessions are explicitly out of scope — the two supported axes are local and claude.ai cloud only. See `.agents/plans/2026-04-20-0928-remote-claude-code-sessions.md` (Scope boundary).

**Supersedes**: `.agents/plans/2026-04-12-0015-remote-ssh-session-visibility.md` (different architecture).

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on (via subagent, per AGENTS.md)
- If blocked, document the blocker inline before stopping

## Overview
Let the local seshctl UI show sessions running on the user's *other* macOS machines (e.g. a home desktop running `claude --remote-control`). Remote rows are informational — they confirm that a session exists on another machine so the user can see their full session landscape in one place. No attach/focus action on remote rows for MVP; the user drives those sessions from the Claude mobile app anyway. Implementation is on-demand SSH exec of `seshctl-cli list --json` on each configured peer; no daemon, no persistent connections, no polling.

## User Experience

**Setup (one-time per peer):**
1. User runs `seshctl-cli peer add home-desktop` on their laptop. The CLI validates the host via `ssh -G home-desktop` (resolves SSH config) and attempts a probe run (`ssh -o ConnectTimeout=5 home-desktop seshctl-cli --version`). On success, stores `home-desktop` in the local `peers` table. On failure, prints the ssh stderr (e.g. "Permission denied (publickey)") and exits non-zero without writing the peer.
2. `seshctl-cli peer list` prints configured peers with last-successful-fetch status.
3. `seshctl-cli peer remove home-desktop` deletes the row.

**Daily use:**
1. User opens the floating panel (⌘⇧S).
2. Local sessions appear immediately, as today.
3. In parallel, the view model fires one SSH subprocess per configured peer (`ssh home-desktop seshctl-cli list --json`). Results stream in and merge into the list over the next ~200ms–2s depending on SSH latency.
4. Remote sessions render as `SessionRowView` with an added "remote · home-desktop" badge. Sort order interleaves with local sessions by recency, same as the existing list.
5. If a peer fails (network down, host unreachable, `seshctl-cli` missing on remote), a single synthetic row appears: `home-desktop · unreachable` with the underlying error message on hover/inspection. No crash, no silent hide.
6. Enter on a remote row is a no-op for MVP (future: deep-link to claude.ai when enumeration lands). The row renders without the usual focus affordance — dimmed chevron or removed entirely — to signal non-actionability.
7. While the panel stays open, the list refreshes on the existing poll timer (local DB read) but peer fetches are rate-limited: a per-peer 30-second cache prevents re-fetching on every tick. Closing and reopening the panel invalidates the cache for immediate refresh.

**Edge cases user experiences:**
- First `peer add` with broken SSH → clean error, no partial state.
- ControlMaster configured → subsequent fetches feel instant (reuse multiplexed connection). Without it, each fetch is ~200–500ms cold.
- Peer's `seshctl-cli` is older and doesn't support `--json` → treated same as "unreachable" with a clearer error hint ("update seshctl-cli on home-desktop").

## Architecture

**Runtime data flow when the panel opens:**

```
SeshctlApp (local)
  ├── SessionListViewModel
  │     ├── local DB poll (existing) ──► ~/.local/share/seshctl/seshctl.db
  │     └── peer fetch (NEW) ──► PeerFetcher
  │                                ├── reads `peers` table from local DB
  │                                └── for each peer, spawns:
  │                                    Process("ssh", [host, "seshctl-cli", "list", "--json"])
  │                                    → parses JSON → [Session] with remoteHost = host
  │
  └── UI merges local + remote sessions into one sorted list
```

**What lives where:**
- **Local DB** (`~/.local/share/seshctl/seshctl.db`): adds a `peers` table. Remote sessions are **never persisted locally** — they live only in the view model's memory for the lifetime of the panel's visibility. Closing the panel drops them.
- **Remote machine**: runs unmodified `seshctl-cli` (with the new `--json` flag). Remote machine has no knowledge of the local machine; it just responds to the subprocess invocation over SSH. SSH is the auth boundary — if the user can SSH to the host as themselves, they can read their own session DB on that host.
- **No daemon**, no Unix socket, no launchd plist, no persistent subprocess. Every fetch is a fresh `ssh` invocation (or a multiplexed channel if ControlMaster is configured — SSH handles that transparently).

**Performance characteristics:**
- Cold SSH (no ControlMaster): ~200–500ms per peer per fetch. Dominated by TCP + TLS + auth handshake.
- Warm SSH (ControlMaster on): ~30–80ms per fetch. Just the command round-trip.
- Per-peer cache TTL of 30s means the worst case is one fetch every 30 seconds per peer *while the panel is open*. Panel closed = zero traffic.
- Fetches run in parallel across peers (independent subprocesses), so N peers adds O(max(latency)) not O(sum), to first render.

**State persistence:**
- `peers` table: host strings + last_successful_fetch timestamp (for UI status display).
- No remote session caching in local DB. Deliberate choice: staleness semantics are simpler if remote rows only exist while we can actually confirm them.

**Failure modes:**
- SSH fails: the subprocess exits non-zero, PeerFetcher captures stderr, surfaces a synthetic "unreachable" row instead of the peer's sessions. Other peers are unaffected (independent subprocesses).
- JSON parse fails (remote seshctl-cli too old): same treatment — "unreachable" with hint.
- Timeout: PeerFetcher hard-kills subprocess after 10s; surfaces as "timeout" error row.

## Current State

- `seshctl-cli list` subcommand exists in `Sources/seshctl-cli/SeshctlCLI.swift` (listed in Start/Update/End/List/Show/GC). Need to confirm whether it supports JSON output; if not, add `--json` flag.
- `Database.swift` uses GRDB with a sequential migration pattern (currently at v8, `launch_directory`). WAL mode enabled for multi-process read safety.
- `Session.swift` is a Codable struct with 21 fields.
- `SessionListViewModel` polls the local DB on a timer and publishes to `SessionListView`.
- `SessionRowView` renders rows with status icon, title, host app badge. Existing row variants include active, inactive (recent), and recall search results.
- `SessionAction.execute()` is the single entry point for Enter on any row — we'll add a `.remoteSession` target type that currently does nothing (MVP) but keeps the architecture clean.
- `TerminalController` uses `Process` API to spawn subprocesses (osascript, open). `RecallService` is the richest existing subprocess example — stream stdout, capture stderr, handle termination. **Use RecallService as the template for PeerFetcher.**
- No existing network or IPC code. This is a fresh subsystem, but the subprocess pattern is established.

## Proposed Changes

**Strategy**: introduce a minimal `peers` concept (table + CLI + fetcher), extend `seshctl-cli list` with `--json`, and plumb remote sessions into the view model as a parallel input alongside the local DB read. No changes to the canonical session action routing; remote rows are rendered but not actionable.

**Why this approach over the alternatives discussed:**
- *vs peer daemon + Unix socket over SSH*: Avoided because it adds launchd lifecycle, IPC protocol, and persistent connection management for no gain — we're not doing attach. The SSH-exec approach is 10× less code for the same user-visible outcome.
- *vs persisting remote sessions in local DB*: Avoided because staleness reasoning gets ugly (when do we GC a remote row? what if the peer's DB was rolled back?). Live query means the list is always accurate to the last fetch.
- *vs push/streaming updates*: Over-engineered for a list that updates every few seconds at most. On-demand fetch is both simpler and honest about when data is fresh.

### Complexity Assessment

**Low.** ~7 files modified, 2 new files, ~300–400 LOC. No new architectural patterns; reuses the `Process`-based subprocess approach from RecallService and the Codable/GRDB pattern from existing migrations. Risk surface:
- New `--json` output on `seshctl-cli list` is a public contract; once shipped, remote machines with older `seshctl-cli` will break. Mitigate by version-gating: check remote version during `peer add`, print warning if version mismatch.
- SSH subprocess management edge cases (hanging ssh, zombie processes on app quit) — reuse RecallIndexingProcess's termination pattern.
- View model concurrency: merging async peer results into the observable list without flicker. Use a stable sort key (session id) and replace rather than append.

No existing tests to break. No schema ambiguity. No cross-cutting concerns beyond what's enumerated.

## Impact Analysis

- **New Files**:
  - `Sources/SeshctlCore/Peer.swift` — `Peer` struct (host, lastFetchedAt), `PeerFetchError` enum.
  - `Sources/SeshctlCore/PeerFetcher.swift` — subprocess-based fetcher. Spawns `ssh host seshctl-cli list --json`, parses, returns `[Session]` with `remoteHost` set. Based on the RecallService subprocess pattern.
  - `Tests/SeshctlCoreTests/PeerFetcherTests.swift` — mocks subprocess via protocol injection, tests success / timeout / non-zero exit / malformed JSON / version mismatch.
  - `Tests/SeshctlCoreTests/PeerCRUDTests.swift` — tests add/remove/list DB operations.

- **Modified Files**:
  - `Sources/SeshctlCore/Database.swift` — migration v9: `CREATE TABLE peers (host TEXT PRIMARY KEY, added_at INTEGER NOT NULL, last_fetched_at INTEGER)`. Add `addPeer`, `removePeer`, `listPeers`, `updatePeerFetchTime` methods.
  - `Sources/SeshctlCore/Session.swift` — add `public var remoteHost: String?` field. NOT persisted (not in CodingKeys for DB), but present in JSON codec output so remote sessions can carry their host through serialization. Reconsider: could be a separate wrapper type to keep `Session` clean — see Key Decisions.
  - `Sources/seshctl-cli/SeshctlCLI.swift` — add `Peer` parent subcommand with `add/remove/list` children. Add `--json` flag to `List` subcommand; when set, emit `[Session]` as JSON to stdout.
  - `Sources/SeshctlUI/SessionListViewModel.swift` — inject `PeerFetcher`, kick off peer fetches when the panel becomes visible, merge results into the published session list. Per-peer 30s cache. Cancel in-flight fetches on panel close.
  - `Sources/SeshctlUI/SessionRowView.swift` — render a "remote · <host>" badge when `session.remoteHost != nil`. Dim or hide the focus chevron for remote rows.
  - `Sources/SeshctlUI/SessionAction.swift` — accept a remote session target (no-op dispatch for MVP). Keep architecture honest so future deep-linking has a home.
  - `Tests/SeshctlCoreTests/DatabaseTests.swift` — add tests for v9 migration and peer CRUD.
  - `Tests/SeshctlUITests/SessionListViewModelTests.swift` — tests for peer fetch merge, cache behavior, failure rendering.

- **Dependencies**:
  - Relies on: existing `Process`/subprocess patterns (RecallService is the template), GRDB migrator, existing `Session` Codable, `ssh` + `seshctl-cli` binary present on remote host.
  - Relied on by: nothing yet. This is a leaf feature.

- **Similar Modules** (reuse audit):
  - **`RecallService` / `RecallIndexingProcess`** (`Sources/SeshctlCore/RecallService.swift`): canonical subprocess-management pattern in this repo — `Process.terminationHandler`, `NSLock`-protected state, stderr streaming, waiter continuations. `PeerFetcher` should mirror this structure rather than re-inventing subprocess management.
  - **`TerminalController.runAppleScript`**: simpler subprocess pattern for one-shot command + capture. Don't use this — peer fetch needs proper timeout and error surface that RecallService already models.
  - **`SystemEnvironment` protocol** (`TerminalController.swift`): abstracts OS side-effects for testability. `PeerFetcher` should take a similar protocol so tests can inject a fake subprocess runner without actually spawning `ssh`.
  - **Session row rendering with badges**: `SessionRowView` already renders a host-app badge. Extend that pattern for the remote-host badge — do not create a new row view type.
  - **Migration template**: migrations v2–v8 in `Database.swift`. v9 follows the same shape (additive, no destructive changes, WHERE-guarded idempotency if any UPDATE is needed — not needed here since it's a new table).

## Key Decisions

1. **Remote sessions live in memory only, never in the local DB.** Chose live-query over cache to avoid stale-row reasoning. Cost: if a peer is briefly unreachable, its rows disappear and reappear. Acceptable — matches "no polling, on-demand fetch" philosophy.
2. **`Session.remoteHost` as an optional field vs a wrapper type.** Add the field directly to `Session` (optional, not persisted) rather than introducing `RemoteSession`/`LocalSession` variants. Rationale: the view model, row view, and action router all treat remote and local sessions identically except at two points (badge + action dispatch). A single struct with an optional host field is less code than a sum type. Cost: a field that's always nil for local rows. Worth it.
3. **No attach / focus action on remote rows for MVP.** User is uncertain about the desired action ("perhaps I just use the web UI from the other machine"). Ship visibility first; add deep-link or attach later if a clear action emerges. Remote rows render without a focus chevron so the non-actionability is visually obvious.
4. **`--json` output for `seshctl-cli list` is a new public contract.** Gate via `seshctl-cli --version` check on `peer add`; version-mismatch peers surface as "unreachable: please update seshctl-cli on <host>" rather than silently misbehaving.
5. **Per-peer 30s fetch cache.** Balances "panel feels live" against "don't hammer SSH." Invalidated on panel open. Not exposed to user as a setting in MVP.
6. **10-second hard timeout per SSH fetch.** Peer that hangs longer is declared unreachable and killed. Prevents zombie ssh processes.
7. **No auth beyond SSH.** As discussed: SSH is the trust boundary. No tokens, no certs. If the user can `ssh host`, they can read their own session DB on that host. No new auth surface for seshctl to own.
8. **MVP is macOS-to-macOS.** GRDB doesn't support Linux; deferring cross-OS to a future plan.

## Implementation Steps

### Step 1: Add `--json` flag to `seshctl-cli list`
- [ ] Modify `Sources/seshctl-cli/SeshctlCLI.swift` `List` subcommand to accept a `--json` flag.
- [ ] When set, encode `[Session]` with `JSONEncoder` (ISO8601 dates, key strategy matching existing CodingKeys) and print to stdout.
- [ ] Confirm existing non-JSON output is unchanged.
- [ ] Manual sanity check: `seshctl-cli list --json | jq '.[0].id'` returns a valid UUID string.

### Step 2: Schema migration v9 + Peer CRUD in `Database.swift`
- [ ] Add migration `v9_create_peers` to `Database.swift` creating `peers` table: `host TEXT PRIMARY KEY, added_at INTEGER NOT NULL, last_fetched_at INTEGER`.
- [ ] Add methods: `addPeer(host:)`, `removePeer(host:)`, `listPeers() -> [Peer]`, `updatePeerFetchTime(host:at:)`.
- [ ] Create `Sources/SeshctlCore/Peer.swift` with `public struct Peer: FetchableRecord, PersistableRecord, Codable { var host: String; var addedAt: Date; var lastFetchedAt: Date? }`.

### Step 3: Add `peer` subcommands to `seshctl-cli`
- [ ] Add `Peer` parent subcommand with children `Add`, `Remove`, `List`.
- [ ] `peer add <host>`: run `ssh -G <host>` to validate SSH config resolution; run `ssh -o ConnectTimeout=5 <host> seshctl-cli --version` to probe; insert into DB on success; print clean error and exit 1 on failure.
- [ ] `peer list`: print table of host + last-fetched-at.
- [ ] `peer remove <host>`: delete from DB, print confirmation.

### Step 4: `PeerFetcher` + `remoteHost` field on `Session`
- [ ] Add `public var remoteHost: String?` to `Session.swift`. Do NOT add to `CodingKeys` (so it never round-trips through the local DB). Mark with a comment that it's a transient/in-memory-only field populated by `PeerFetcher`.
- [ ] Create `Sources/SeshctlCore/PeerFetcher.swift`. Protocol: `protocol PeerFetcher { func fetch(host: String) async throws -> [Session] }`. Real impl spawns `ssh <host> seshctl-cli list --json`, 10s timeout, parse, set `remoteHost` on each returned Session. Model after `RecallIndexingProcess`.
- [ ] Define `PeerFetchError` enum: `.unreachable(String)`, `.timeout`, `.versionMismatch`, `.malformedOutput`.

### Step 5: View model integration
- [ ] Modify `SessionListViewModel` to accept an injected `PeerFetcher`.
- [ ] On panel visibility change to visible: read peers from DB, fire concurrent `fetch(host:)` calls, merge results into published session list. Store per-peer last-fetch timestamp + cache TTL (30s). Track in-flight tasks so they can be cancelled on panel close.
- [ ] On peer fetch failure: publish a sentinel "unreachable" session-like row with an error message string.
- [ ] Ensure UI update happens on main actor; no flicker when peer results arrive after local list render (use stable sort + diff).

### Step 6: UI — remote badge + no-op action
- [ ] Modify `SessionRowView` to render a "remote · <host>" badge when `session.remoteHost != nil`. Reuse existing badge styling.
- [ ] Hide or dim the focus chevron for remote rows (visually signal non-actionable).
- [ ] Add `.remoteSession(Session)` case to `SessionAction.Target` (or equivalent). `SessionAction.execute` dispatches it to a no-op with a log/toast "Remote sessions have no action yet."

### Step 7: Write tests
- [ ] `Tests/SeshctlCoreTests/PeerCRUDTests.swift`: v9 migration runs clean; addPeer/removePeer/listPeers round-trip; addPeer is idempotent on duplicate host; updatePeerFetchTime updates the column.
- [ ] `Tests/SeshctlCoreTests/PeerFetcherTests.swift` (with injectable subprocess runner): success path parses a fixture JSON and sets `remoteHost` on every returned session; timeout path surfaces `.timeout`; non-zero exit surfaces `.unreachable(stderr)`; malformed JSON surfaces `.malformedOutput`.
- [ ] `Tests/SeshctlCoreTests/DatabaseTests.swift`: add one test that seeds a pre-v9 DB (or starts fresh) and asserts `peers` table exists with correct schema after migrator run.
- [ ] `Tests/SeshctlUITests/SessionListViewModelTests.swift`: injecting a fake PeerFetcher → view model merges remote sessions into list with badge present; failing peer → "unreachable" sentinel appears and doesn't kill the list; 30s cache prevents second fetch within TTL.
- [ ] Existing tests: update any Session initializer that doesn't already set `remoteHost: nil` (mechanical, similar to launch_directory rollout).
- [ ] Run `swift test` via subagent; confirm all green.

### Step 8: Manual verification
- [ ] Set up: on a second macOS machine, install the updated `seshctl-cli`. Ensure `ssh <otherhost>` works from the test laptop.
- [ ] Run `seshctl-cli peer add <otherhost>` — confirm success message.
- [ ] Run `seshctl-cli list --json` on the remote via `ssh <otherhost>` — confirm JSON output is valid.
- [ ] Start a `claude --remote-control` session on the remote machine.
- [ ] Open seshctl's floating panel on the laptop — confirm the remote session appears with the "remote · <otherhost>" badge, interleaved with local sessions by recency.
- [ ] Unplug network (or block ssh); reopen panel — confirm the peer renders as "unreachable" with error, local sessions still render cleanly.
- [ ] Press Enter on remote row — confirm no-op (with optional transient toast).

### Step 9: Docs
- [ ] Update `README.md` or relevant section: document `seshctl-cli peer add/remove/list`, note the SSH-config prerequisite, note that remote sessions are informational in MVP.
- [ ] Update `AGENTS.md` compatibility table if applicable.

## Acceptance Criteria

- [ ] [test] `seshctl-cli list --json` emits a JSON array of Session objects with all current fields; round-trips through `JSONDecoder`.
- [ ] [test] v9 migration creates `peers` table; addPeer/removePeer/listPeers/updatePeerFetchTime all work.
- [ ] [test] `PeerFetcher` parses a fixture remote response and stamps `remoteHost` on every returned session.
- [ ] [test] `PeerFetcher` timeout path surfaces `.timeout` within ~10s without leaking the ssh subprocess.
- [ ] [test] `PeerFetcher` malformed-JSON path surfaces `.malformedOutput`; non-zero exit surfaces `.unreachable(stderr)`.
- [ ] [test] `SessionListViewModel` with injected fake PeerFetcher: remote sessions appear in the merged list with `remoteHost` populated; failing peer produces a sentinel without crashing other peers' results.
- [ ] [test] 30s cache: within TTL, no second fetch is issued for the same peer.
- [ ] [test-manual] On a real 2-machine setup: `peer add` + open panel → remote `claude --remote-control` session appears with "remote · <host>" badge.
- [ ] [test-manual] Peer unreachable → UI shows clean error row, doesn't break the rest of the list.
- [ ] [test-manual] Enter on a remote row is a no-op (or a clear "not yet actionable" message).

## Edge Cases

- **ControlMaster not configured**: each fetch opens a fresh SSH connection (~200–500ms). Acceptable for MVP. Document that enabling ControlMaster improves perf.
- **Remote `seshctl-cli` missing or older than this version**: `peer add` probes via `--version`; mismatched versions are stored with a warning ("update seshctl-cli on <host>"). At fetch time, if `--json` isn't supported, fetch fails as `.unreachable` with an actionable error message.
- **Remote machine asleep / network down**: fetch fails, synthetic "unreachable" row appears; user can continue working; next panel open retries.
- **User has 10+ peers**: still fine — fetches are parallel; only cost is file-descriptor usage for N concurrent ssh subprocesses. No known upper bound worth enforcing.
- **Session ID collision between local and remote**: Session IDs are UUIDv4; collision probability negligible. If it happens, dedup by `(remoteHost, id)` tuple — local wins for the no-host case.
- **Laptop sleeps while panel is open**: SSH subprocesses may hang; 10s timeout kills them on wake. View model's cancellation on panel close also covers wake-after-close.
- **Remote's `seshctl-cli list` hangs (e.g. GRDB contention with a concurrent seshctl-cli write on the remote)**: 10s hard timeout kicks in; peer surfaces as timeout; next fetch retries fresh.
- **`peer add` with a host that was already added**: idempotent — overwrite `added_at` or leave it, either is fine. Don't error.
