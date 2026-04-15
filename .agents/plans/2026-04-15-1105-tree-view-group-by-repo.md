# Plan: Tree View — Group Active Sessions by Repo and Folder

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on (`make test`, 30s timeout; `make kill-build` on hang)
- If blocked, document the blocker here before stopping

## Overview
Add a second top-level view mode to the seshboard that groups **active** sessions into a vertical tree by repo (or directory name for non-repo sessions). The user toggles between the existing flat list and the tree with a keyboard shortcut. Mode persists across panel reopens via `UserDefaults`.

## User Experience

1. User opens the seshboard (Cmd+Shift+S). It shows the current flat list by default.
2. User presses `v` — the list regroups into a repo-grouped tree:
   - Each repo is a section header (e.g. `ios-2`) with a count badge (`3`). Header rows are visual only (no chevron, no tap action — no collapse/expand in MVP).
   - Under each repo, one row per active session in that repo. If the session's launch folder differs from the repo name (`nonStandardDirName`), the folder name is shown in blue next to the session row (same styling as today).
   - Sessions not associated with a git repo are collected under a synthetic group named after their **directory's own `lastPathComponent`** (e.g. `~/scratch/foo` → group "foo"). No "No repo" catch-all.
   - Only **active** sessions appear in tree view. Recent sessions are only visible in list mode.
   - Repo groups are sorted alphabetically by repo/group name. Within a group, sessions are sorted by `updatedAt` descending (most recent first).
3. `j` / `k` / arrow keys / `tab` move the selection between session rows in the tree. Group headers are visual only — they are never selectable and are skipped by vertical navigation. `gg` / `G` jump to top/bottom session.
4. `enter` / `e` on a session focuses/resumes it exactly as in list mode. `x`, `o`, `u` behave identically. Group headers have no keyboard action.
5. Pressing `v` again toggles back. On every toggle the currently selected session's id is looked up in the new ordering — if present, selection stays on it; if missing (e.g., a recent session selected in list mode then toggling to tree — recents are excluded from tree view), selection falls back to the first row, or to no-selection if the new ordering is empty.
6. Search (`/`) is disabled in tree mode: pressing `/` flips `isTreeMode` to false and activates search in the same keystroke. (Keeps search semantics simple — search is inherently flat.)
7. The header count ("N active") is unchanged. The footer shortcut hint shows `v list`/`v tree` based on the current mode.

**No collapse/expand in MVP.** Groups are always fully shown. `h`/`l`/`←`/`→` are not handled in tree mode.

## Architecture

**Today's runtime flow (list view):**
- `AppDelegate` creates a `FloatingPanel` hosting `RootView` → `SessionListView` bound to a `SessionListViewModel`.
- `SessionListViewModel` observes the DB via `SessionStore`, exposes `activeSessions`, `recentSessions`, `orderedSessions` (active + recent), and a `selectedIndex: Int` over the flat ordered list.
- `SessionListView` renders a `LazyVStack` over `orderedSessions`. Keyboard events flow from `AppDelegate`'s `NSEvent` monitor → viewmodel mutations (`selectedIndex`, search state, etc.).
- Actions dispatch through `SessionAction.execute()` using `viewModel.orderedSessions[selectedIndex]`.

**Tree view at runtime:**
- `@Published var isTreeMode: Bool` lives on `SessionListViewModel` (NOT `@AppStorage` — `@AppStorage` is a `DynamicProperty` that doesn't fire `objectWillChange` inside `ObservableObject` classes, so views bound to the viewmodel wouldn't re-render on toggle). The viewmodel stores an injected `UserDefaults` (`init(..., defaults: UserDefaults = .standard)`). Initial value is `defaults.bool(forKey: "seshctl.isTreeMode")` in `init`. A `didSet` on `isTreeMode` writes `defaults.set(isTreeMode, forKey: "seshctl.isTreeMode")`. This gives proper SwiftUI publication and testable persistence.
- When `isTreeMode == true`, the viewmodel computes `treeGroups: [SessionGroup]` from `activeSessions` only:
  - Grouping key = `session.primaryName` (from the existing `SessionRowView` helper): `gitRepoName` if present, else the session directory's own `lastPathComponent` (e.g. `~/scratch/foo` → `foo`).
  - Each `SessionGroup` has: `name: String`, `sessions: [Session]`, `isRepo: Bool` (derived from `session.gitRepoName != nil` for sessions in the group). Group uniqueness keys off `(name, isRepo)` so a non-repo group named `ios-2` doesn't collide with a repo group named `ios-2` (they render as separate adjacent groups).
  - Sort: groups alphabetically by `name.lowercased()` (ties broken by `isRepo` = true first); sessions inside by `updatedAt` descending.
- The viewmodel exposes `treeOrderedSessions: [Session]` — the flat session sequence in group/session order (group headers are **not** included in this sequence). `selectedIndex` indexes into this sequence in tree mode.
- **`orderedSessions` itself becomes mode-aware** — it returns `activeSessions + recentSessions` in list mode or `treeOrderedSessions` (active-only) in tree mode. This replaces the previously proposed `effectiveOrderedSessions`. Single source of truth; no parallel ordering property. Note the asymmetry: tree mode **excludes recent sessions** deliberately (see Key Decisions → Active-only).
- `SessionListView` reads `viewModel.isTreeMode` and renders either the existing list body or a new `SessionTreeView` subview. The tree renders each `SessionGroup` as a non-selectable `GroupHeaderView` (chevron-free — no collapse in MVP) followed by its sessions. Session rows reuse the existing `SessionRowView` and are the only selectable rows in tree mode.
- **`ScrollViewReader` id scheme:** `GroupHeaderView` rows use `.id("group-\(group.name)-\(group.isRepo)")`; session rows keep `"\(session.id)-\(session.status.rawValue)"`. `proxy.scrollTo` on selection change targets only session-row ids (headers are never selected).
- **View toggle action (`v`)** in `AppDelegate` calls `viewModel.toggleViewMode()`. The viewmodel captures the currently selected session, flips `isTreeMode`, then remaps `selectedIndex` by **matching `session.id`**: find that session in the new `orderedSessions`; if not present (e.g., a recent session selected in list mode then toggling to tree — recents are excluded from tree), fall back to index `0`; if the new `orderedSessions` is empty, `selectedIndex = -1`.
- **`selectedIndex = -1` is the empty-selection sentinel.** Every mutation of `selectedIndex` (move handlers, tap, remap, search-entry) must preserve the sentinel when `orderedSessions.isEmpty` — not clamp `-1` to `0`. Step 2 audits every mutation site and a test exercises `j`/`k` against an empty list.
- **Search activation from tree mode bypasses `toggleViewMode()`** to avoid a wasted by-id remap. The `/` handler sets `isTreeMode = false` directly, then calls the existing search-enter handler (which resets `selectedIndex = 0`).
- No DB changes, no migrations, no new persisted data beyond `isTreeMode`. Grouping runs on whatever `activeSessions` holds in memory.
- **No collapse/expand in MVP.** `h`/`l`/`←`/`→` are not handled; group headers are purely visual. Rationale: keeps `selectedIndex` invariants trivial, removes all `collapsedGroupNames` state, removes the "hide sessions" transition and clamping concerns. Re-add only if users ask.

**Shared helper extraction:**
- `SessionRowView.primaryName` and `nonStandardDirName` move to a new extension on `Session` in `Sources/SeshctlUI/Session+Display.swift` (UI module — helpers are display-layer string formatting used only by UI call sites). No behavior change in list mode.

## Current State
- `Sources/SeshctlUI/SessionListView.swift` — flat `LazyVStack` with Active/Recent/Semantic sections.
- `Sources/SeshctlUI/SessionListViewModel.swift` — `activeSessions`, `recentSessions`, `orderedSessions`, `selectedIndex`, search, recall.
- `Sources/SeshctlUI/SessionRowView.swift:158-167` — `primaryName` and `nonStandardDirName` helpers that already solve the repo-vs-folder display (folder name rendered in blue when distinct from repo). We reuse this logic for grouping.
- `Sources/SeshctlApp/AppDelegate.swift:107-226` — keyboard event handling; dispatches to viewmodel.
- `Sources/SeshctlUI/SessionAction.swift` — single entry point for session actions; unchanged.
- No existing view-mode toggle or UserDefaults usage for UI state (verified — none found in Sources).

## Proposed Changes

**Where the work lands:**
1. Extract `primaryName` / `nonStandardDirName` to a shared `Session` extension in `Sources/SeshctlUI/Session+Display.swift` (read by the row view and the grouping code).
2. Add `@AppStorage("seshctl.isTreeMode") var isTreeMode: Bool`, `treeGroups`, `treeOrderedSessions`, and `toggleViewMode()` to `SessionListViewModel`. Inject `UserDefaults` in init so tests can pass an isolated suite.
3. Make `orderedSessions` itself mode-aware (returns list sequence in list mode, `treeOrderedSessions` in tree mode). No `effectiveOrderedSessions` — single source of truth.
4. Split `SessionListView` so it dispatches on `isTreeMode`: existing list body when false, new `SessionTreeView` subview when true.
5. Add `SessionTreeView.swift` and `GroupHeaderView` (non-selectable) that render groups/sessions; reuse `SessionRowView` for the leaves.
6. Extend `AppDelegate` keyboard handling: `v` toggles mode; `/` auto-switches to list first. `h`/`l`/`←`/`→` are not handled.
7. Update footer hint in `SessionListView` to show the current-mode shortcut line.

**Why this approach over alternatives:**
- Keeping `selectedIndex: Int` over a flat session sequence (headers not included) means all existing key handlers (`j`/`k`/`enter`/`x`/`o`/`u`/`gg`/`G`) continue to work unchanged.
- `@AppStorage` + `Bool` keeps persistence trivial and avoids enum + raw-value decoding. Promote to enum only when a third mode appears.
- Dropping collapse/expand from the MVP eliminates `collapsedGroupNames`, `toggleGroupCollapseAtSelection`, and all clamping-on-hide concerns. Scope can grow if users ask.
- No DB changes: grouping is a pure derivation from already-stored `gitRepoName` + `directory`. Reversible.
- Disabling search in tree mode (by auto-switching to list on `/`) avoids designing tree-level search highlights and recall layout.

### Complexity Assessment
**Low-to-medium.** ~5 files changed: `SessionListViewModel` (new state + derived collections + mode-aware `orderedSessions`), `SessionListView` (mode dispatch + footer), new `SessionTreeView` + `GroupHeaderView`, new `Session+Display.swift` (extracted helpers), `SessionRowView` (delete moved helpers), `AppDelegate` (one new keybinding). No DB migration, no new dependencies, no changes to `SessionAction`/`TerminalController`. Main risk area: selection remapping by `session.id` on mode toggle — covered by viewmodel tests. Low regression risk on list mode because the existing code path is preserved (only `orderedSessions` gains a mode branch).

## Impact Analysis
- **New Files:**
  - `Sources/SeshctlUI/SessionTreeView.swift` (tree body + `GroupHeaderView`)
  - `Sources/SeshctlUI/Session+Display.swift` (shared `primaryName` / `nonStandardDirName`)
  - `Tests/SeshctlUITests/SessionTreeGroupingTests.swift`
- **Modified Files:**
  - `Sources/SeshctlUI/SessionListViewModel.swift` — add `@AppStorage isTreeMode`, `treeGroups`, `treeOrderedSessions`, `toggleViewMode`; make `orderedSessions` mode-aware; inject `UserDefaults` in init
  - `Sources/SeshctlUI/SessionListView.swift` — branch on `isTreeMode`; update footer hint
  - `Sources/SeshctlUI/SessionRowView.swift` — delete moved helpers, use `Session+Display`
  - `Sources/SeshctlApp/AppDelegate.swift` — handle `v` (reuse existing single-letter-shortcut guard); route `/` through mode switch
  - `Tests/SeshctlUITests/SessionListViewModelTests.swift` — add tree-mode tests
- **Dependencies:** none new. Relies on SwiftUI `@AppStorage` and manual chevron-free header row rendering.
- **Similar Modules:** `SessionRowView.primaryName`/`nonStandardDirName` (reused); Active/Recent `sectionHeader` styling in `SessionListView:242-252` (reuse as `GroupHeaderView` base).

## Key Decisions
- **Grouping key derivation:** reuse the existing `primaryName`/`nonStandardDirName` logic from `SessionRowView`. Repo-backed sessions group by `gitRepoName`; non-repo sessions group by the directory's own `lastPathComponent`. Extracted into `Session+Display.swift` (UI module).
- **Active-only in tree view:** recent sessions are excluded from tree mode entirely.
- **Toggle via keyboard only:** `v` cycles modes. No toolbar UI (discoverable via footer hint).
- **No collapse/expand in MVP.** Groups always fully shown; `h`/`l`/`←`/`→` unhandled. Revisit if users ask.
- **Bool + `@AppStorage` over enum:** two states, no third planned. Promote to enum when needed.
- **`orderedSessions` is mode-aware.** No parallel `effectiveOrderedSessions`. Single navigation source of truth.
- **Selection remap by `session.id`** on toggle; fall back to index 0 if missing; `-1` if the target ordering is empty.
- **`selectedIndex = -1` is the empty-selection sentinel.** Existing handlers already bounds-check.
- **Group uniqueness keyed by `(name, isRepo)`.** Prevents a non-repo folder-named group from colliding with a repo of the same name.
- **Search forces list mode:** pressing `/` in tree mode switches to list, then enters search.

## Implementation Steps

### Step 1: Extract shared display helpers
- [x] Create `Sources/SeshctlUI/Session+Display.swift` with a `Session` extension exposing `primaryName: String` (gitRepoName or dir lastPathComponent) and `nonStandardDirName: String?` (dir lastPathComponent when distinct from repo name). Same logic as `SessionRowView:158-167` today.
- [x] Update `Sources/SeshctlUI/SessionRowView.swift` to delete the local `primaryName`/`nonStandardDirName` and read from the extension.
- [x] Build and confirm list view still renders repo+folder exactly as before.

### Step 2: Add tree state and derivations to the viewmodel
- [x] In `Sources/SeshctlUI/SessionListViewModel.swift`, accept `defaults: UserDefaults = .standard` in init; store it as a private instance property. Update `AppDelegate`'s call site to pass the default.
- [x] Add `@Published var isTreeMode: Bool`. Initialize in `init` from `defaults.bool(forKey: "seshctl.isTreeMode")`. Add a `didSet` that writes the new value back via `defaults.set(isTreeMode, forKey: "seshctl.isTreeMode")`. (Do NOT use `@AppStorage` — it doesn't trigger `objectWillChange` inside an `ObservableObject` class.)
- [x] Declare `struct SessionGroup { let name: String; let isRepo: Bool; let sessions: [Session] }`. Group key = `(session.primaryName, session.gitRepoName != nil)`.
- [x] Add computed `treeGroups: [SessionGroup]`: walk `activeSessions`, bucket by that key. Sort groups by `name.lowercased()` (isRepo=true wins ties); sort sessions inside by `updatedAt` descending.
- [x] Add computed `treeOrderedSessions: [Session]` that flattens `treeGroups` in group/session order (headers NOT included).
- [x] Make `orderedSessions` mode-aware: in list mode return the existing `activeSessions + recentSessions`; in tree mode return `treeOrderedSessions`. All existing call sites (AppDelegate, `onTapGesture`, `proxy.scrollTo`, `SessionAction` dispatch) remain unchanged.
- [x] Add `toggleViewMode()`: capture the currently selected `Session?` (if `selectedIndex >= 0`), flip `isTreeMode`, then find that session's id in the new `orderedSessions`; set `selectedIndex` to the new index, or `0` if not found, or `-1` if empty.
- [x] **Audit `selectedIndex` mutation sites.** Enumerate every writer of `selectedIndex` (move up/down, page up/down, `gg`/`G`, tap, search-enter, `toggleViewMode`) and confirm each either guards on `orderedSessions.count > 0` or preserves `-1` when empty. Do not use `max(0, selectedIndex - 1)` or `min(count - 1, selectedIndex + 1)` patterns that would clobber the `-1` sentinel. Early-return when `orderedSessions.isEmpty`.

### Step 3: Render the tree
- [x] Create `Sources/SeshctlUI/SessionTreeView.swift` with a `ScrollViewReader` + `LazyVStack` iterating `viewModel.treeGroups`. For each group: render a `GroupHeaderView` (name + session count; no chevron, non-selectable, no tap gesture) with `.id("group-\(group.name)-\(group.isRepo)")`. Then iterate the group's sessions and render `SessionRowView` with `.id("\(session.id)-\(session.status.rawValue)")` — unchanged from list mode.
- [x] Each session row's `isSelected` comes from `index-in-treeOrderedSessions == selectedIndex`; `onTapGesture` updates `selectedIndex` and routes through `SessionAction.execute()`.
- [x] In `Sources/SeshctlUI/SessionListView.swift`, branch the body: when `viewModel.isTreeMode && !isSearching`, render `SessionTreeView`; else render the existing list path. Update the footer hint to swap between `v tree` and `v list` based on mode. (Footer hint deferred to Step 6.)

### Step 4: Wire keyboard actions
- [x] In `Sources/SeshctlApp/AppDelegate.swift`, add a handler for the `v` key that calls `viewModel.toggleViewMode()`. Gate with the same predicate as existing single-letter shortcuts (`e`, `x`, `o`, `u`): `!viewModel.isSearching && viewModel.pendingKillSessionId == nil && !viewModel.pendingMarkAllRead`.
- [x] On `/` when `isTreeMode == true`: set `isTreeMode = false` **directly** (do NOT call `toggleViewMode()` — avoids a wasted by-id remap), then invoke the existing search-enter handler (which resets `selectedIndex = 0`). Since NSEvent handling is synchronous, both effects land in the same tick.
- [x] Verify `j`/`k`/`tab`/`enter`/`x`/`o`/`u`/`gg`/`G` already work because they operate on `selectedIndex` over `orderedSessions`, which is now mode-aware.

### Step 5: Write tests
- [ ] Create `Tests/SeshctlUITests/SessionTreeGroupingTests.swift`. Test cases:
  - Sessions with same `gitRepoName` group under that repo.
  - Session without `gitRepoName` groups by the directory's own `lastPathComponent`.
  - Group sort is alphabetical case-insensitive; within group, sessions sort by `updatedAt` descending.
  - Non-repo group named `X` and repo group named `X` render as two distinct `SessionGroup` entries (uniqueness by `(name, isRepo)`).
  - Only active sessions appear in `treeGroups` (recent sessions excluded).
  - `treeOrderedSessions` flattens groups in order; header rows are NOT in the sequence.
- [ ] Extend `Tests/SeshctlUITests/SessionListViewModelTests.swift`. Tests use an isolated `UserDefaults(suiteName:)` passed through viewmodel init:
  - `toggleViewMode()` remaps `selectedIndex` by `session.id` and keeps the same session selected (list→tree and back).
  - `toggleViewMode()` falls back to index 0 when the session isn't in the new ordering (e.g., selected a Recent session in list mode, toggle to tree — Recent sessions aren't in tree).
  - `toggleViewMode()` sets `selectedIndex = -1` when the new `orderedSessions` is empty.
  - `isTreeMode` round-trips through the injected `UserDefaults` (construct a new viewmodel with the same store; initial `isTreeMode` matches the prior write).
  - Entering search from tree mode sets `isTreeMode = false` before search activates.
  - **Sentinel preservation:** with an empty `orderedSessions`, calling move-up / move-down / page-up / page-down / `gg` / `G` leaves `selectedIndex` at `-1` (does not clobber to `0`).

### Step 6: Manual verification and docs
- [ ] `make install` and exercise: list → tree with `v`; move with `j`/`k` (headers are never highlighted); focus a session with `enter`; kill with `x`; `/` to search (verify switch to list); toggle back with `v`. Verify mode persists across panel close/reopen.
- [ ] Update the footer hint string in `SessionListView` to swap between `v tree` / `v list`.
- [ ] Update `README.md` compatibility / usage section if it documents shortcuts. (Skip if no shortcut table exists.)

## Acceptance Criteria
- [ ] [test] Sessions sharing a `gitRepoName` group under that repo in tree mode; non-repo sessions group by the directory's own `lastPathComponent`.
- [ ] [test] Group order is alphabetical case-insensitive; session order within a group is by `updatedAt` descending.
- [ ] [test] Non-repo group `X` and repo group `X` render as two distinct `SessionGroup` entries.
- [ ] [test] Only active sessions appear in tree view; recent sessions are absent.
- [ ] [test] `toggleViewMode()` preserves the selected session by `session.id` across the switch.
- [ ] [test] `toggleViewMode()` falls back to index 0 when the session isn't in the new ordering, and to `-1` when the new ordering is empty.
- [ ] [test] `isTreeMode` round-trips through the injected `UserDefaults` suite.
- [ ] [test] Entering search while in tree mode sets `isTreeMode = false` before search activates.
- [ ] [test] Move / page / `gg` / `G` preserve `selectedIndex = -1` when `orderedSessions` is empty.
- [ ] [test-manual] Pressing `v` in the panel toggles between the flat list and the tree view.
- [ ] [test-manual] `j`/`k` in tree mode only moves across session rows; group headers are never highlighted.
- [ ] [test-manual] Pressing `enter` on a tree row focuses/resumes the session identically to list mode.
- [ ] [test-manual] Folder name (when different from repo) still renders in blue next to the session row in tree view (shared helper verified).

## Edge Cases
- **Session with `gitRepoName` present but directory outside the repo** (rare): grouped by repo name; directory shown as-is on the row.
- **Directory is filesystem root or a single-component path**: `lastPathComponent` returns the path itself (e.g. `/` → `/`, `/tmp` → `tmp`); render as-is.
- **Session directory is exactly `~`**: group name is `~` (home-tilde); no special handling.
- **All active sessions in one repo**: single group; still render a header for visual consistency.
- **Zero active sessions in tree mode**: show the same "No sessions" empty state as list mode (no tree scaffolding).
- **Last session in a repo becomes inactive**: group disappears on next refresh. If that session was selected, remap by `session.id` → not found → `selectedIndex = 0` (or `-1` if the tree is now empty).
- **Tree mode with no active sessions, user presses `v`**: mode flips to list normally; `selectedIndex` lands on first recent session if any.
