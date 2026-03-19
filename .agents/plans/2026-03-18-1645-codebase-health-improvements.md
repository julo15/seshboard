# Plan: Codebase Health Improvements

## Working Protocol
- Use parallel subagents for independent steps (e.g., test additions for different files can be parallelized)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run `make test` after each step before moving on (timeout 30s per AGENTS.md)
- If build hangs, run `make kill-build` before retrying
- Steps are ordered by priority: security fixes first, then test coverage, then refactoring, then robustness/performance

## Overview
Address all 7 improvement areas identified in the codebase health audit: fix AppleScript injection, add transcript path validation, bring test coverage above 60% for all logic files, add tests for untested critical modules, extract keyboard routing from AppDelegate, add hook failure logging, and implement transcript streaming for large files.

## User Experience
1. **AppleScript injection fix**: No visible change — window focusing continues to work, but directory names with special characters (newlines, control chars) no longer break or inject into AppleScript.
2. **Path validation**: No visible change — transcripts still load, but paths are now canonicalized and validated.
3. **Test coverage**: No visible change — internal quality improvement only.
4. **KeyboardRouter extraction**: No visible change — keyboard shortcuts work identically.
5. **Hook failure logging**: Hook errors now log to `~/.local/share/seshboard/hooks.log` instead of being silently discarded. Users can diagnose broken hooks.
6. **Transcript streaming**: Large sessions load without memory pressure. No UI change.

## Current State

### Security
- `WindowFocuser.swift:291-294`: `escapeForAppleScript` only escapes `\` and `"`, not newlines or control characters
- `TranscriptParser.swift:9-18`: `session.transcriptPath` used directly from DB without canonicalization

### Test Coverage (below 60% threshold)
- `SessionListViewModel.swift`: 45.8% — missing search/kill flow tests
- `SessionDetailViewModel.swift`: 28.3% — only error cases tested
- `HostAppResolver.swift`: 0% — completely untested (102 lines)
- `Install.swift`: 0% — completely untested (482 lines)
- `SeshboardCLI.swift`: 0% — completely untested (265 lines)

### Architecture
- `AppDelegate.swift` (312 lines): Lines 96-230 are keyboard event routing mixed with app bootstrap

### Robustness
- All hook scripts (`hooks/**/*.sh`) redirect stderr to `/dev/null` with `&` — silent failures
- `SessionDetailViewModel.swift:45`: Loads entire transcript file into memory via `Data(contentsOf:)`

## Proposed Changes

### Security Hardening
- Expand `escapeForAppleScript` to strip/escape newlines, tabs, and other control characters that could break AppleScript string literals
- Add path canonicalization in `TranscriptParser.transcriptURL` — resolve symlinks and validate the path is within expected directories (`~/.claude/` or the session's own directory)

### Test Coverage
- Add tests for `SessionListViewModel` search mode and kill confirmation flows to bring coverage above 60%
- Add tests for `SessionDetailViewModel.load()` successful path
- Create `HostAppResolverTests.swift` with mocked NSRunningApplication scenarios
- Create `InstallTests.swift` testing JSON/TOML manipulation logic (mock file system)
- Create `CLITests.swift` testing command parsing and database interactions

### Architecture
- Extract keyboard handling from `AppDelegate` into a new `KeyboardRouter` class that receives key events and delegates to the appropriate ViewModel. AppDelegate instantiates it and forwards `keyDown` events.

### Robustness
- Modify hook scripts to append errors to a log file while still backgrounding
- Replace full-file `Data(contentsOf:)` in `SessionDetailViewModel` with line-by-line streaming via `FileHandle` or buffered reading

## Impact Analysis
- **New Files**:
  - `Sources/SeshboardApp/KeyboardRouter.swift` — extracted keyboard routing
  - `Tests/SeshboardUITests/HostAppResolverTests.swift`
  - `Tests/SeshboardCLITests/InstallTests.swift`
  - `Tests/SeshboardCLITests/CLITests.swift`
- **Modified Files**:
  - `Sources/SeshboardUI/WindowFocuser.swift` — AppleScript escaping fix
  - `Sources/SeshboardCore/TranscriptParser.swift` — path validation
  - `Sources/SeshboardUI/SessionDetailViewModel.swift` — streaming reads
  - `Sources/SeshboardApp/AppDelegate.swift` — extract keyboard routing
  - `hooks/claude/*.sh`, `hooks/codex/*.sh` — error logging
  - `Tests/SeshboardUITests/SessionListViewModelTests.swift` — add search/kill tests
  - `Tests/SeshboardUITests/SessionDetailViewModelTests.swift` — add load success test
  - `Package.swift` — add SeshboardCLITests target (if needed)
- **Dependencies**: No new external dependencies
- **Similar Modules**: `WindowFocuserTests` already demonstrates the mock pattern (SystemEnvironment) — reuse for HostAppResolver testing

## Implementation Steps

### Step 1: Fix AppleScript injection
- [ ] Update `escapeForAppleScript` in `Sources/SeshboardUI/WindowFocuser.swift` to also escape newlines (`\n` → `\\n`), carriage returns (`\r` → `\\r`), tabs (`\t` → `\\t`), and other control characters
- [ ] Add test cases in `Tests/SeshboardUITests/WindowFocuserTests.swift` for special character escaping (newlines, tabs, unicode)
- [ ] Run `make test` to verify

### Step 2: Add transcript path validation
- [ ] In `Sources/SeshboardCore/TranscriptParser.swift`, add `resolvingSymlinksInPath()` and validate the resolved path is within `~/.claude/` or matches the session directory
- [ ] Add test cases in `Tests/SeshboardCoreTests/TranscriptParserTests.swift` for path traversal attempts and symlink resolution
- [ ] Run `make test` to verify

### Step 3: Bring SessionListViewModel above 60% coverage
- [ ] Add tests to `Tests/SeshboardUITests/SessionListViewModelTests.swift` for:
  - `enterSearch()` / `exitSearch()` state transitions
  - `appendSearchCharacter()` / `deleteSearchCharacter()` filtering behavior
  - `confirmKill()` flow (with mock process)
  - `moveToTop()` / `moveToBottom()` boundary behavior
- [ ] Run `swift test --enable-code-coverage` and verify SessionListViewModel > 60%

### Step 4: Bring SessionDetailViewModel above 60% coverage
- [ ] Add tests to `Tests/SeshboardUITests/SessionDetailViewModelTests.swift` for:
  - Successful transcript load (write temp JSONL file, verify turns parsed)
  - Load with missing file (verify error state)
  - Load with empty file (verify empty turns)
- [ ] Run coverage check and verify > 60%

### Step 5: Add HostAppResolver tests
- [ ] Create `Tests/SeshboardUITests/HostAppResolverTests.swift`
- [ ] Test `resolve(session:)` with various session configurations (bundleId present, bundleId missing, pid present, pid missing)
- [ ] Test known terminal bundle ID matching
- [ ] Run `make test` to verify

### Step 6: Add Install.swift tests
- [ ] Add `SeshboardCLITests` test target to `Package.swift` if not present
- [ ] Create `Tests/SeshboardCLITests/InstallTests.swift`
- [ ] Test JSON settings manipulation (add hooks, idempotent re-add, preserve existing hooks)
- [ ] Test TOML config manipulation (add feature flag, preserve existing content)
- [ ] Test hook file copying logic
- [ ] Run `make test` to verify

### Step 7: Add CLI command tests
- [ ] Create `Tests/SeshboardCLITests/CLITests.swift`
- [ ] Test `Start`, `Update`, `End` commands with temporary database
- [ ] Test `List`, `Show` output formatting
- [ ] Test `GC` duration parsing (`30d`, `7d`, `24h`)
- [ ] Run `make test` to verify

### Step 8: Extract KeyboardRouter from AppDelegate
- [ ] Create `Sources/SeshboardApp/KeyboardRouter.swift` with keyboard handling logic from AppDelegate lines ~96-230
- [ ] KeyboardRouter should accept references to `SessionListViewModel`, `SessionDetailViewModel?`, and `NavigationState`
- [ ] Move `handleKey`, `handleNormalKey`, `handleSearchKey`, `handleDetailKey` methods
- [ ] Update `AppDelegate.swift` to instantiate `KeyboardRouter` and forward `keyDown` events
- [ ] Run `make test` to verify no regressions
- [ ] Run `make run-app` to manually verify keyboard shortcuts work

### Step 9: Add hook failure logging
- [ ] Modify all `hooks/claude/*.sh` scripts: change `> /dev/null 2>&1 &` to `>> "$LOG" 2>&1 &` where `LOG=~/.local/share/seshboard/hooks.log`
- [ ] Modify all `hooks/codex/*.sh` scripts similarly
- [ ] Add log rotation: truncate log if > 1MB at the start of each hook invocation
- [ ] Test manually by running a hook script with a broken seshboard-cli path

### Step 10: Stream large transcripts
- [ ] Modify `Sources/SeshboardUI/SessionDetailViewModel.swift` to use `FileHandle` for line-by-line reading instead of `Data(contentsOf:)`
- [ ] Modify `Sources/SeshboardCore/TranscriptParser.swift` `parse` methods to accept a line iterator or stream instead of full `Data`
- [ ] Ensure existing tests still pass with the new streaming approach
- [ ] Run `make test` to verify

## Acceptance Criteria
- [ ] [test] AppleScript escaping handles newlines, carriage returns, tabs — verified by unit tests
- [ ] [test] Transcript path traversal attempts return nil — verified by unit tests
- [ ] [test] SessionListViewModel coverage > 60% (currently 45.8%)
- [ ] [test] SessionDetailViewModel coverage > 60% (currently 28.3%)
- [ ] [test] HostAppResolver has test coverage > 60%
- [ ] [test] Install.swift JSON/TOML manipulation covered by tests
- [ ] [test] CLI commands (Start, Update, End, GC) covered by tests
- [ ] AppDelegate.swift reduced from 312 to ~150 lines
- [ ] KeyboardRouter.swift created and handles all key events
- [ ] Hook scripts log errors to `~/.local/share/seshboard/hooks.log`
- [ ] Large transcript files load without full memory allocation
- [ ] All existing tests continue to pass (`make test`)

## Edge Cases
- AppleScript escaping: directory names with `»` (AppleScript chevron), null bytes, or emoji
- Path validation: symlinked home directories, paths with `..` that resolve to valid locations
- Hook logging: log file permissions if seshboard directory doesn't exist yet
- Streaming: transcript file modified while being read (Claude actively writing)
- KeyboardRouter: ensure modifier keys (Cmd, Ctrl, Shift) still propagate correctly after extraction
