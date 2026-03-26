# Plan: Unify Session Focus/Resume into Single Action Pipeline

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on
- If blocked, document the blocker here before stopping

## Overview
Consolidate three disparate Enter-key handlers (`focusSession`, `resumeSession`, `handleRecallResult`) into a single `SessionAction.execute()` pipeline, and merge `WindowFocuser` + `SessionResumer` into a unified `TerminalController` type. This eliminates duplicated bundle ID maps, inconsistent app resolution strategies, and divergent fallback behavior.

## User Experience
No user-visible behavior changes. The same actions (focus active session, resume closed session, handle recall result) continue to work the same way. The improvement is in reliability — every row type now goes through the same tested code path, so edge cases that work for one row type automatically work for all.

## Architecture

### Current Runtime Flow (3 divergent paths)

When the user presses Enter, AppDelegate checks what's selected and dispatches to one of three methods:

1. **Active session** → `focusSession()` → `WindowFocuser.focus(pid:directory:)` → PID tree walk to find app → route to TTY/URI/generic focus
2. **Inactive session** → `resumeSession()` → `HostAppResolver.resolve()` to find app → `SessionResumer.resume()` → route to AppleScript/URI resume → clipboard fallback
3. **Recall result** → `handleRecallResult()` → match to DB session → if active, call path 1; if inactive, inline app resolution (DB bundleId ?? frontmost) → `SessionResumer.resume()` → clipboard fallback

Each path resolves the target terminal app differently, uses different fallback chains, and accesses the clipboard through different APIs.

### Proposed Runtime Flow (1 unified path)

```
User presses Enter on ANY row
    ↓
AppDelegate calls SessionAction.execute(target)
    ↓
SessionAction resolves a TerminalTarget:
  - What action? (focus existing tab / resume in new tab)
  - Which app? (single resolution chain: DB → PID walk → frontmost → nil)
  - What command? (for resume: built from session or recall result)
    ↓
TerminalController.dispatch(action, app, directory)
  - focus: open -b + TTY script or URI handler
  - resume: open -b + AppleScript do-script or URI handler
  - fallback: copy command to clipboard
```

**Key change**: App resolution happens once, in one place, using the same priority chain regardless of how the user got there. `TerminalController` owns all bundle ID maps, scheme resolution, and AppleScript generation — no duplication.

### What's in memory vs on disk
- Bundle ID maps and known terminal lists: compile-time constants in `TerminalController`
- Session data (hostAppBundleId, conversationId, launchArgs): read from SQLite DB
- `HostAppResolver` cache: in-memory dictionary keyed by session ID (unchanged, still used for UI icon display)
- AppleScript strings: generated on the fly, executed via `osascript`

### Performance characteristics
- No change — the expensive parts (process tree walk, AppleScript execution, `open -b`) remain the same
- Slightly fewer redundant lookups in the recall path (was doing DB lookup + separate frontmost detection)

## Current State

### Key files and their roles

| File | Role | Lines |
|---|---|---|
| `Sources/SeshctlApp/AppDelegate.swift:303-358` | Three Enter-key handlers with divergent logic |
| `Sources/SeshctlUI/WindowFocuser.swift` | Focus active sessions (TTY/URI/generic), owns bundle ID maps, AppleScript escaping, SystemEnvironment protocol |
| `Sources/SeshctlUI/SessionResumer.swift` | Resume inactive sessions, duplicates bundle ID maps, owns resume AppleScript |
| `Sources/SeshctlUI/HostAppResolver.swift` | Resolves app for UI display (icon/name), has its own PID walk + known terminals list |
| `Tests/SeshctlUITests/WindowFocuserTests.swift` | 37 tests covering discovery, scripts, escaping, routing |
| `Tests/SeshctlUITests/SessionResumerTests.swift` | 10 tests covering command building, scripts, routing |

### Specific problems

1. **VS Code bundle IDs defined in 3 places**: `WindowFocuser.vsCodeBundleIds`, `SessionResumer.vsCodeBundleIds`, and scheme mapping in both
2. **Known terminals defined in 3 places**: `WindowFocuser.knownTerminals`, `HostAppResolver.lookupHostApp`, `SessionResumer.detectFrontmostTerminal`
3. **PID tree walk implemented twice**: `WindowFocuser.findAppBundleId` and `HostAppResolver.lookupHostApp` (identical logic, different return types)
4. **App resolution differs per entry point**: PID walk only, HostAppResolver only, or DB field only — never the same chain
5. **Clipboard fallback differs**: `NSPasteboard` directly vs `vm.copyResumeCommand()` — different APIs for the same thing
6. **WindowFocuser missing Cursor scheme**: Maps Cursor to "vscode" instead of "cursor" in `focusVSCode`

## Proposed Changes

### Strategy: Bottom-up consolidation

**Step 1 — Create `TerminalApp` registry**: Single source of truth for bundle IDs, display names, URI schemes, and capabilities (supports TTY focus? supports AppleScript resume? supports URI?).

**Step 2 — Create `TerminalController`**: Merge `WindowFocuser` + `SessionResumer` into one type. It handles:
- `focus(pid:directory:bundleId:)` — activate existing tab (current WindowFocuser logic)
- `resume(command:directory:bundleId:)` — open new tab with command (current SessionResumer logic)
- Shared: bundle ID routing, `open -b` activation, AppleScript generation, escaping
- Shared: `SystemEnvironment` protocol (moved here)
- Shared: `detectFrontmostTerminal()` (already on SessionResumer, now on TerminalController)

**Step 3 — Create `SessionAction`**: Single entry point that AppDelegate calls for any Enter-key press. Takes a `SessionActionTarget` (active session / inactive session / recall result), resolves the app, decides focus vs resume, calls TerminalController, handles clipboard fallback.

**Step 4 — Simplify AppDelegate**: Replace `focusSession()`, `resumeSession()`, `handleRecallResult()` with a single call to `SessionAction.execute()`.

**Step 5 — Clean up HostAppResolver**: Remove PID walk and known terminals (now in TerminalController). Keep it focused on its actual job: resolving icons/names for UI display, using DB-stored values.

### Why this approach over alternatives
- Bottom-up means each step is independently testable and doesn't break existing behavior until the final swap
- `TerminalApp` registry eliminates the root cause (duplicated constants) rather than just the symptoms
- `SessionAction` gives us one place to add logging/debugging for focus issues

### Complexity Assessment
**Medium-high**. Touches 6-8 files, consolidates two existing modules into one, and rewires the main interaction handler. The individual changes are straightforward (moving code, not rewriting logic), but the surface area requires careful testing. Risk of regressions is moderate — mitigated by the existing test suites for WindowFocuser and SessionResumer which we'll adapt rather than rewrite.

## Impact Analysis
- **New Files**:
  - `Sources/SeshctlUI/TerminalApp.swift` — bundle ID registry
  - `Sources/SeshctlUI/TerminalController.swift` — merged focus + resume logic
  - `Sources/SeshctlUI/SessionAction.swift` — unified entry point
  - `Tests/SeshctlUITests/TerminalControllerTests.swift` — merged test suite
  - `Tests/SeshctlUITests/SessionActionTests.swift` — action routing tests
- **Modified Files**:
  - `Sources/SeshctlApp/AppDelegate.swift` — replace 3 methods with 1
  - `Sources/SeshctlUI/HostAppResolver.swift` — simplify to UI-only concerns
- **Deleted Files**:
  - `Sources/SeshctlUI/WindowFocuser.swift` — merged into TerminalController
  - `Sources/SeshctlUI/SessionResumer.swift` — merged into TerminalController
  - `Tests/SeshctlUITests/WindowFocuserTests.swift` — merged into TerminalControllerTests
  - `Tests/SeshctlUITests/SessionResumerTests.swift` — merged into TerminalControllerTests
- **Dependencies**:
  - `TerminalController` depends on `TerminalApp` and `SystemEnvironment`
  - `SessionAction` depends on `TerminalController`, `HostAppResolver`, `Session`, `RecallResult`
  - `AppDelegate` depends on `SessionAction` (replaces direct WindowFocuser/SessionResumer deps)
  - `HostAppResolver` still used by `SessionRowView` and `RecallResultRowView` for icons
- **Similar Modules**: None — this consolidates the existing similar modules

## Key Decisions
- Timing delays (0.3s, 0.5s) are kept as-is — user confirmed these work fine
- `HostAppResolver` stays as a separate type for UI icon resolution — it has `@MainActor` and caching concerns that don't belong in TerminalController
- `SystemEnvironment` protocol moves to TerminalController (or stays as a shared protocol) since it's the testability seam for both focus and resume

## Implementation Steps

### Step 1: Create `TerminalApp` registry
- [x] Create `Sources/SeshctlUI/TerminalApp.swift` with enum/struct for known apps
- [x] Define: bundle ID, display name, URI scheme (optional), capabilities (supportsTTYFocus, supportsAppleScriptResume, supportsURIHandler)
- [x] Include static lookup: `TerminalApp.from(bundleId:) -> TerminalApp?`
- [x] Include `knownTerminals`, `vsCodeApps` as static collections
- [x] Fix Cursor scheme mapping (currently "vscode", should be "cursor")

### Step 2: Create `TerminalController` (merge WindowFocuser + SessionResumer)
- [x] Create `Sources/SeshctlUI/TerminalController.swift`
- [x] Move `SystemEnvironment` protocol and `RealSystemEnvironment` from WindowFocuser
- [x] Move `escapeForAppleScript()`
- [x] Implement `focus(pid:directory:bundleId:)` — current WindowFocuser.focus logic but using TerminalApp for routing
- [x] Implement `resume(command:directory:bundleId:)` — current SessionResumer.resume logic
- [x] Implement `resolveApp(session:)` — single app resolution chain: DB → PID walk → frontmost terminal
- [x] Implement `detectFrontmostTerminal()` — moved from SessionResumer
- [x] Share `buildResumeCommand(session:)` — moved from SessionResumer
- [x] Use `TerminalApp` for all bundle ID routing (eliminates duplicated maps)
- [x] Consolidate focus scripts and resume scripts using TerminalApp capabilities

### Step 3: Create `SessionAction` unified entry point
- [x] Create `Sources/SeshctlUI/SessionAction.swift`
- [x] Define `SessionActionTarget` enum: `.activeSession(Session)`, `.inactiveSession(Session)`, `.recallResult(RecallResult, matchingSession: Session?)`
- [x] Implement `execute(target:viewModel:onDismiss:)`:
  1. Determine action type (focus vs resume) from target
  2. Resolve app via `TerminalController.resolveApp()`
  3. For focus: call `TerminalController.focus()`
  4. For resume: build command, call `TerminalController.resume()`, clipboard fallback on failure
  5. Mark read, remember focused session, dismiss panel
- [x] Single clipboard fallback path using `NSPasteboard`

### Step 4: Rewire AppDelegate
- [x] Replace `focusSession()`, `resumeSession()`, `handleRecallResult()` with calls to `SessionAction.execute()`
- [x] Update Enter-key handlers in normal mode and search mode to construct appropriate `SessionActionTarget`
- [x] Remove imports of WindowFocuser and SessionResumer

### Step 5: Simplify HostAppResolver
- [x] Remove PID tree walk from HostAppResolver (now in TerminalController)
- [x] Remove known terminals fallback list (now in TerminalApp)
- [x] HostAppResolver now: check DB bundleId → look up icon/name → return HostAppInfo
- [x] For live PID lookup (still needed for UI icons of sessions without stored host app), delegate to TerminalController

### Step 6: Delete old files
- [x] Delete `Sources/SeshctlUI/WindowFocuser.swift`
- [x] Delete `Sources/SeshctlUI/SessionResumer.swift`
- [x] Update any remaining references (imports, test helpers)

### Step 7: Write and migrate tests
- [x] Create `Tests/SeshctlUITests/TerminalControllerTests.swift` — migrate all WindowFocuser + SessionResumer tests
- [x] Adapt tests to use TerminalApp enum for bundle IDs
- [x] Create `Tests/SeshctlUITests/SessionActionTests.swift`:
  - [x] Test: active session → focus called with correct PID
  - [x] Test: inactive session with conversationId → resume called with correct command
  - [x] Test: inactive session without conversationId → focus fallback
  - [x] Test: recall result with matching active session → focus
  - [x] Test: recall result with matching inactive session → resume
  - [x] Test: recall result with no matching session → resume with recall's resumeCmd
  - [x] Test: resume failure → clipboard fallback
  - [x] Test: app resolution chain (DB → PID → frontmost → nil)
- [x] Delete `Tests/SeshctlUITests/WindowFocuserTests.swift`
- [x] Delete `Tests/SeshctlUITests/SessionResumerTests.swift`
- [x] Run full test suite, verify all pass

### Step 8: Future-proof against duplication
- [x] **TerminalApp enum — exhaustive switches, no `default` cases**: Every `switch` on `TerminalApp` must be exhaustive (no `default`). This means adding a new terminal app case triggers compiler errors everywhere it needs handling — focus script, resume script, URI scheme, display name. An agent literally cannot add half an integration.
- [x] **Doc comments on entry points**: Add `/// CANONICAL ENTRY POINT — all session focus/resume actions MUST go through this method. Do not create parallel code paths.` on `SessionAction.execute()` and `TerminalController.focus()`/`.resume()`. Agents that read the source will see the warning.
- [x] **Update AGENTS.md**: Replace the "Adding Terminal App Support" section with new instructions:
  1. Add a case to the `TerminalApp` enum — the compiler will guide you to every place that needs a handler
  2. All user actions go through `SessionAction.execute()` — never add focus/resume logic to AppDelegate or views
  3. All terminal interaction goes through `TerminalController` — never call `open -b` or `osascript` directly
  4. All bundle IDs and schemes live in `TerminalApp` — never hardcode them elsewhere
  5. Reference: `TerminalApp.swift` (registry), `TerminalController.swift` (execution), `SessionAction.swift` (routing)

### Step 9: Verify build and manual smoke test
- [x] `make install` — full build + install
- [x] Manual test: focus active session in iTerm2
- [x] Manual test: focus active session in VS Code
- [x] Manual test: resume closed session in iTerm2
- [x] Manual test: resume recall result (no matching DB session)
- [x] Manual test: clipboard fallback when terminal unknown

## Acceptance Criteria
- [x] [test] All existing WindowFocuser tests pass (migrated to TerminalControllerTests)
- [x] [test] All existing SessionResumer tests pass (migrated to TerminalControllerTests)
- [x] [test] SessionAction routes active sessions to focus
- [x] [test] SessionAction routes inactive sessions to resume with correct command
- [x] [test] SessionAction routes recall results through the same pipeline as direct sessions
- [x] [test] App resolution uses single chain: DB → PID walk → frontmost → nil
- [x] [test] Resume failure triggers clipboard fallback
- [x] [test] Cursor scheme correctly maps to "cursor" (bug fix)
- [x] [test-manual] Focus active session works in iTerm2 and VS Code
- [x] [test-manual] Resume closed session works in iTerm2 and VS Code
- [x] [test-manual] Recall result resume works end-to-end
- [x] No duplicated bundle ID definitions anywhere in codebase
- [x] No duplicated known-terminals lists anywhere in codebase
- [x] Adding a new `TerminalApp` case produces compiler errors guiding the implementer to all required handlers
- [x] AGENTS.md documents the extension points so future agents know where to add new apps

## Edge Cases
- **Session with PID but dead process**: `resolveApp` PID walk fails → falls back to DB bundleId → falls back to frontmost terminal
- **Recall result with no matching DB session and no frontmost terminal**: clipboard fallback with recall's `resumeCmd`
- **Session with no conversationId and no PID**: nothing to focus or resume → no-op (matches current behavior)
- **VS Code not running but stored as hostAppBundleId**: `open -b` will launch VS Code → URI handler sent → works (macOS launches the app)
- **Multiple known terminals running**: `detectFrontmostTerminal` prefers the frontmost one, then falls back to first known running
