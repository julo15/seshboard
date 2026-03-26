# Plan: Simplify Recall Result Resume Path

## Working Protocol
- Small, focused change — can be done in a single pass
- Run `make test` after changes to verify nothing breaks
- Build timeout: 120s, test timeout: 30s

## Overview
Remove the `matchingSession` distinction from recall results. The two code paths (matching vs no matching session) converge to identical behavior, and the green dot indicator is misleading — it shows "active" for any DB match, not just live sessions.

## User Experience
All recall results now show a uniform magnifying glass icon instead of green dot vs magnifying glass. Pressing Enter on any recall result always uses the recall result's own `resumeCmd` and `project` to resume. No change in actual resume behavior (both paths already ended up at the same `detectFrontmostTerminal()` + `resume()` call).

## Architecture
**Current:** When the user presses Enter on a recall result, `SessionAction.handleRecallResult` checks if a matching session exists in the DB via `matchingSession(for:)`. If found and active, it focuses the existing tab. If found and inactive, it builds a resume command from the session's DB data (which may lose flags like `--dangerously-skip-permissions`). If not found, it uses the recall result's `resumeCmd` directly. In practice, `host_app_bundle_id` is always NULL, so both inactive paths resolve the terminal identically via `detectFrontmostTerminal()`.

**After:** All recall results go through a single path: use `result.resumeCmd` and `result.project`, detect the terminal via `detectFrontmostTerminal()`, and call `resume()`. The `matchingSession` lookup is removed from the recall flow entirely.

## Current State
- **`SessionAction.swift`** — `handleRecallResult` has two branches: matching session (active/inactive) and no matching session
- **`SessionActionTarget`** — `.recallResult(RecallResult, matchingSession: Session?)` carries the optional session
- **`RecallResultRowView.swift`** — `hasMatchingSession: Bool` drives green dot vs magnifying glass
- **`SessionListView.swift:142`** — computes `hasMatch = viewModel.matchingSession(for: result) != nil`
- **`AppDelegate.swift:308`** — passes `vm.matchingSession(for: result)` when building the target
- **`SessionListViewModel.swift:291-293`** — `matchingSession(for:)` method
- **Tests:** 3 recall tests in `SessionActionTests.swift` (active match, inactive match, no match), 2 `matchingSession` tests in `SessionListViewModelTests.swift`

## Proposed Changes
Collapse the recall result path to always use the recall result's own data. Remove all `matchingSession` plumbing from the recall flow.

### Complexity Assessment
Low. 6 files touched but all changes are deletions or simplifications — no new patterns, no new logic. Regression risk is minimal since we're converging to the simpler of two equivalent paths.

## Impact Analysis
- **New Files**: None
- **Modified Files**:
  - `Sources/SeshctlUI/SessionAction.swift` — simplify `handleRecallResult`, simplify `SessionActionTarget.recallResult`
  - `Sources/SeshctlUI/RecallResultRowView.swift` — remove `hasMatchingSession`, always show magnifying glass
  - `Sources/SeshctlUI/SessionListView.swift` — remove `hasMatch` computation
  - `Sources/SeshctlApp/AppDelegate.swift` — remove `matchingSession` lookup from target construction
  - `Sources/SeshctlUI/SessionListViewModel.swift` — remove `matchingSession(for:)` if no longer used elsewhere
  - `Tests/SeshctlUITests/SessionActionTests.swift` — collapse 3 recall tests into 1-2 simpler tests
  - `Tests/SeshctlUITests/SessionListViewModelTests.swift` — remove `matchingSession` tests
- **Dependencies**: None external. `matchingSession(for:)` is only used in the recall flow.
- **Similar Modules**: None

## Implementation Steps

### Step 1: Simplify SessionActionTarget
- [x] Remove `matchingSession: Session?` from `.recallResult` case in `SessionAction.swift` — change to `.recallResult(RecallResult)`

### Step 2: Simplify handleRecallResult
- [x] Collapse `handleRecallResult` to a single path: always use `result.resumeCmd` and `result.project`, always use `detectFrontmostTerminal()` for bundleId, always fall back to clipboard on failure
- [x] Remove the `matchingSession` parameter and all branching on it
- [x] Remove `markRead` and `rememberFocused` parameters from `handleRecallResult` (no session to mark/remember)

### Step 3: Update call sites
- [x] `AppDelegate.swift:308` — change to `.recallResult(result)`, remove `vm.matchingSession(for: result)`
- [x] `SessionListView.swift:142` — remove `hasMatch` computation
- [x] `SessionListView.swift:146` — remove `hasMatchingSession` parameter from `RecallResultRowView`

### Step 4: Simplify RecallResultRowView
- [x] Remove `hasMatchingSession` property
- [x] Always show magnifying glass icon (remove green dot branch)

### Step 5: Clean up SessionListViewModel
- [x] Remove `matchingSession(for:)` method if no other callers exist (grep to confirm)

### Step 6: Update tests
- [x] `SessionActionTests.swift` — remove "recall with active matching session" and "recall with inactive matching session" tests; keep/update "recall result resumes" test to verify the single path (uses `result.resumeCmd`, calls `resume()`, dismisses)
- [x] `SessionActionTests.swift` — keep/update "resume failure copies to clipboard" test for the recall path
- [x] `SessionListViewModelTests.swift` — remove `matchingSessionFindsMatch` and `matchingSessionNoMatch` tests

## Acceptance Criteria
- [ ] [test] Recall result resume uses `result.resumeCmd` directly (not session's `buildResumeCommand`)
- [ ] [test] Recall result resume falls back to clipboard when no terminal is available
- [ ] [test-manual] All recall results show magnifying glass icon (no green dots)
- [ ] [test-manual] Pressing Enter on a recall result opens a new terminal tab with the resume command
