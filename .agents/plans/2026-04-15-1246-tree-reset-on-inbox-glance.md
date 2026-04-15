# Plan: Reset Tree View to List on Fresh Panel Open

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on (`swift test`, 30s timeout; `make kill-build` on hang)
- If blocked, document the blocker here before stopping

## Overview
If the user was in tree mode and reopens the seshboard after more than 10 seconds, the panel shows list mode — treating a fresh open as an "inbox glance" where you see what's actionable (or confirm nothing is). The flip is transient: it does not overwrite the persisted `isTreeMode` preference, so pressing `v` immediately returns to tree mode and that write sticks. Reopens within 10 seconds never swap the view — avoids the "it switched on me" surprise during quick close/reopen bursts.

## User Experience

1. User presses `Cmd+Shift+S` and switches to tree view with `v`. Mode persists via `UserDefaults` as before.
2. User closes the panel (click-outside, `q`, `Esc`, or hotkey-toggle-off).
3. Scenario A — **reopens within 10 seconds:** tree view stays as-is. Nothing magical happens.
4. Scenario B — **reopens after more than 10 seconds:** panel shows list view (active + recent). The persisted preference is still "tree". Pressing `v` flips back to tree and that write persists normally.
5. Scenario C — **first-open-after-install** (no stored close time): behaves like Scenario B for anyone whose persisted preference happens to be tree. In practice, a brand-new install starts in list anyway, so this is a no-op.

No UI copy changes. No new keybindings. No new visible affordances. The only user-visible effect is the deliberate "land on list when you come back later" behavior.

## Architecture

**Current state (from PR #14):**
- `SessionListViewModel` has `@Published var isTreeMode: Bool` with a `didSet` that writes to an injected `UserDefaults` under `seshctl.isTreeMode`.
- `v` flips `isTreeMode` via `toggleViewMode()`, which persists through `didSet`.
- `SessionListView` renders list when `!isTreeMode || isSearching`, else `SessionTreeView`.
- `AppDelegate` shows/hides the panel via: `applicationDidFinishLaunching` (initial), `togglePanel()` (hotkey), `dismissPanel()` (keyboard `q`/`Esc` and session actions), and `panelRef.onDismiss` (click-outside).

**Runtime flow after this change:**
- On every panel-close path, `viewModel.recordPanelClose()` writes `Date().timeIntervalSince1970` to `seshctl.lastClosedAt` in the injected `UserDefaults`.
- On every panel-show path, before the existing `panelDidShow()` call, AppDelegate invokes `viewModel.applyInboxAwareResetIfNeeded()`. The viewmodel:
  - Returns immediately if `!isTreeMode`.
  - Reads `lastClosedAt` (defaults to 0 if unset). If `now - lastClosedAt <= 10`, returns without changing anything.
  - Otherwise transiently sets `isTreeMode = false` using a `suppressIsTreeModePersistence` flag around the write so `didSet` skips the `UserDefaults.set(...)` call.
- After the transient flip, any subsequent `toggleViewMode()` (from the `v` key) runs without the suppression flag, so the user's explicit choice persists.
- No new persisted data beyond the single `lastClosedAt` `TimeInterval`. No session-signature tracking (scope was simplified — the user wants the reset to happen even if nothing has changed, to confirm "nothing to action").

**Invariants preserved:**
- `selectedIndex` sentinel (`-1` for empty). The transient flip goes through `isTreeMode.didSet` → `orderedSessions` becomes mode-aware → no direct `selectedIndex` write occurs from the reset. Selection remains whatever it was (typically `0` or `-1` on a fresh open).
- `toggleViewMode()` side effects (clearing `pendingKillSessionId` / `pendingMarkAllRead`) are not triggered by the reset. That's correct: the reset isn't a user toggle, it's a view presentation policy.

## Current State
- `Sources/SeshctlUI/SessionListViewModel.swift` — owns `isTreeMode` + `didSet` persistence.
- `Sources/SeshctlApp/AppDelegate.swift` — has four show/hide paths as noted above.
- `Tests/SeshctlUITests/SessionListViewModelTests.swift` — already uses injected `UserDefaults(suiteName:)` per-test.

## Proposed Changes

**Where the work lands:**
1. `SessionListViewModel`: add `lastClosedAtKey`, `suppressIsTreeModePersistence` flag + `didSet` guard, `recordPanelClose(now:)`, `applyInboxAwareResetIfNeeded(now:burstWindow:)`.
2. `AppDelegate`: call `recordPanelClose()` on every hide path and `applyInboxAwareResetIfNeeded()` before every show path.
3. Tests: six new cases in `SessionListViewModelTests.swift`.

**Why this shape:**
- The reset policy lives on the viewmodel (testable without AppKit). AppDelegate only wires lifecycle hooks.
- `Date` is injected via method parameter so tests don't need wall-clock waits.
- A single `suppressIsTreeModePersistence` flag is cheaper and more local than introducing a separate "transient" property that views would also have to consult.
- No session-signature hash — earlier design included it but the user decided seeing the list even when nothing has changed is valuable (confirms "nothing to action"). Dropping the signature removes surface area and one persistence key.

### Complexity Assessment
**Low.** Three files changed (one source, one app, one test). No new types, no new UI, no migration. Risk surface: (1) the wiring has to cover all show/hide paths — AppDelegate has four, easy to miss one — verified manually by grepping `panelDidShow` / `panelDidHide`. (2) The persistence suppression flag must be balanced; tests assert the persisted value is unchanged after the flip.

## Impact Analysis
- **New Files:** none.
- **Modified Files:**
  - `Sources/SeshctlUI/SessionListViewModel.swift` — new `lastClosedAtKey` static, `suppressIsTreeModePersistence` flag, `didSet` guard, `recordPanelClose`, `applyInboxAwareResetIfNeeded`.
  - `Sources/SeshctlApp/AppDelegate.swift` — wire the two viewmodel methods to all four lifecycle hooks.
  - `Tests/SeshctlUITests/SessionListViewModelTests.swift` — six new cases.
- **Dependencies:** none new. Uses the already-injected `UserDefaults` store.
- **Similar Modules:** `isTreeMode.didSet` already writes through to `defaults`. The new flag reuses that path with a short-circuit.

## Key Decisions
- **Time only, no signature.** User decided the view should reset even when sessions are unchanged — it confirms "nothing to action." Drops a persistence key and simplifies the logic.
- **10-second burst window.** User picked "less than 15s"; 10s is the conservative choice that still prevents accidental-close-reopen surprises.
- **Transient flip, not persisted.** The user's explicit `isTreeMode` preference stays in `UserDefaults`. Only `v` writes through; the inbox-aware reset is view-presentation policy.
- **Viewmodel owns the policy.** Keeps it unit-testable; AppDelegate is a dumb wiring layer.

## Implementation Steps

### Step 1: Add persistence suppression + lifecycle methods to SessionListViewModel
- [x] In `Sources/SeshctlUI/SessionListViewModel.swift`:
  - Add static `private static let lastClosedAtKey = "seshctl.lastClosedAt"`.
  - Add `private var suppressIsTreeModePersistence: Bool = false`.
  - Update `isTreeMode.didSet` to early-return when `suppressIsTreeModePersistence == true` — otherwise keep existing `defaults.set(isTreeMode, forKey: ...)` behavior.
  - Add `public func recordPanelClose(now: Date = Date())` that writes `now.timeIntervalSince1970` to `lastClosedAtKey`.
  - Add `@discardableResult public func applyInboxAwareResetIfNeeded(now: Date = Date(), burstWindow: TimeInterval = 10) -> Bool`:
    - Return `false` if `!isTreeMode`.
    - Read `lastClosedAt = defaults.double(forKey: lastClosedAtKey)` (returns `0.0` if missing).
    - If `now.timeIntervalSince1970 - lastClosedAt <= burstWindow`, return `false`.
    - Set `suppressIsTreeModePersistence = true`, set `isTreeMode = false`, set flag back to `false`. Return `true`.

### Step 2: Wire AppDelegate lifecycle hooks
- [x] In `Sources/SeshctlApp/AppDelegate.swift`:
  - `applicationDidFinishLaunching` (initial show): call `viewModel.applyInboxAwareResetIfNeeded()` before `panelDidShow()`.
  - `togglePanel()` show-branch: same.
  - `togglePanel()` hide-branch: call `viewModel.recordPanelClose()` before `panelDidHide()`.
  - `dismissPanel()` (handles `q`/`Esc`): same as hide-branch.
  - `panelRef.onDismiss` (click-outside): same as hide-branch.

### Step 3: Write tests
- [x] Extend `Tests/SeshctlUITests/SessionListViewModelTests.swift` (use isolated `UserDefaults(suiteName:)` per test via existing helpers):
  - `applyInboxAwareResetIfNeeded does nothing in list mode`.
  - `applyInboxAwareResetIfNeeded does nothing within burst window (≤ 10s)` — include boundary at exactly 10s.
  - `applyInboxAwareResetIfNeeded flips to list when > 10s elapsed`, AND assert `defaults.bool(forKey: "seshctl.isTreeMode") == true` (persistence NOT touched).
  - `recordPanelClose writes lastClosedAt to defaults`.
  - After a transient flip, `toggleViewMode()` restores tree mode and persists the write (and a follow-up toggle persists list mode).
  - First-open-after-install: no `lastClosedAt` stored → reads as 0 → flips if in tree mode. Document in the test.

## Acceptance Criteria
- [x] [test] `applyInboxAwareResetIfNeeded` is a no-op in list mode.
- [x] [test] `applyInboxAwareResetIfNeeded` is a no-op when called within the 10s burst window, including the exact boundary.
- [x] [test] `applyInboxAwareResetIfNeeded` flips `isTreeMode = false` in memory when > 10s elapsed, but leaves `seshctl.isTreeMode` in `UserDefaults` set to `true`.
- [x] [test] `recordPanelClose` writes the current time to `seshctl.lastClosedAt`.
- [x] [test] After a transient flip, `toggleViewMode()` restores tree mode AND persists `true` to `seshctl.isTreeMode`.
- [x] [test] With no `lastClosedAt` stored (first open), a tree-mode viewmodel flips to list on call.
- [ ] [test-manual] Open seshboard, `v` to tree, close, wait 15s, reopen — lands on list. `v` again puts back in tree; close+reopen within 15s still lands on tree.
- [ ] [test-manual] Within 5s close/reopen, view never flips.

## Edge Cases
- **First-open-after-install**: `lastClosedAt` missing → reads as `0.0` → treated as "very long ago" → flips if tree mode. Acceptable: a user who had tree-mode persisted then reinstalled (unlikely) gets one extra "landed in list" open. No harm.
- **System clock moves backward** (NTP correction, manual change): `now - lastClosedAt` could be negative, which is `<= 10` → treated as within burst window → no flip. Acceptable degradation.
- **Panel left open across app restart**: `recordPanelClose` won't fire, so `lastClosedAt` reflects the previous close. Next open after `> 10s` resets to list. Acceptable.
- **Rapid double-toggle via hotkey** (show-hide-show within 10s): second show is within burst window → tree mode preserved. Matches intent.
- **User disables the feature?** Not exposed as a toggle. If needed later, expose a `UserDefaults` flag; not in MVP scope.
