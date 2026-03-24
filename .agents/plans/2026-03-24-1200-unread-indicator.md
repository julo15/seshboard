# Plan: Unread Session Indicator

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them — a fresh agent should be able to find where to resume
- Run tests after each step before moving on
- If blocked, document the blocker here before stopping

## Overview
Add an "Unread" tag to session rows so users can see which sessions have had actionable changes since they last focused on them. Sessions are marked read when the user presses Enter/e to focus. Only actionable states trigger unread — in-progress (working/waiting) changes are ignored.

## User Experience

1. User opens the panel after being away. Several sessions have changed.
2. Sessions that completed, went idle (Claude done responding), or became stale since the user last focused them show an "Unread" pill/tag to the right of the folder name and tool badge.
3. Sessions currently in working/waiting state do NOT show the tag — nothing to act on yet.
4. User presses Enter/e on a session to focus it. That session's unread tag disappears (marked read).
5. If a read session later transitions to idle or completed, the tag reappears.
6. Brand new sessions that the user has never focused show "Unread" once they reach an actionable state (idle after initial setup, or completed).

## Architecture

**Current flow:** CLI hooks write session changes to SQLite → UI polls every 2s → `SessionListViewModel.refresh()` fetches sessions → `SessionRowView` renders each row.

**What changes at runtime:**
- A new nullable `last_read_at` column stores when the user last "read" (focused) each session. `nil` means never read.
- On each poll, the view model computes unread status per session: `updatedAt > lastReadAt` (or `lastReadAt == nil`) AND status is in `{idle, completed, canceled, stale}`.
- This is a lightweight in-memory comparison — no extra DB queries. The `lastReadAt` value is already fetched as part of the session row.
- When the user presses Enter/e, `markSessionRead(id:)` writes `last_read_at = NOW` to the DB. This is a single row UPDATE — fast and non-blocking.
- The unread set is stored as a `Set<String>` on the view model and passed down to `SessionRowView` as a boolean.

**State persistence:** DB column means it survives app restarts and is automatically cleaned up by the existing GC (sessions older than 30 days are deleted, taking their `last_read_at` with them).

## Current State

- **Session model** (`Sources/SeshctlCore/Session.swift`): Has `updatedAt` and `status` fields. No read-tracking.
- **Database** (`Sources/SeshctlCore/Database.swift`): GRDB migrations v1-v3. No `last_read_at` column.
- **SessionListViewModel** (`Sources/SeshctlUI/SessionListViewModel.swift`): `rememberFocusedSession()` exists for focus memory (30s selection restore), but doesn't persist read state.
- **SessionRowView** (`Sources/SeshctlUI/SessionRowView.swift`): Row layout is `[status dot] [time] [folder + tool badge] [spacer] [host icon] [chevron]`. The tag goes after the tool badge.
- **AppDelegate** (`Sources/SeshctlApp/AppDelegate.swift`): `focusSession()` calls `rememberFocusedSession()` then dismisses panel.

## Proposed Changes

**Approach:** Add a `lastReadAt` column to the session, compute unread status in the view model, and render a tag in the row view.

Why DB column over UserDefaults: the session lifecycle (creation, GC, deletion) is already managed by the DB. A column keeps read state co-located and auto-cleaned. The CLI never touches this column — it's purely UI-side state written by the app.

Why compute in VM instead of the view: the VM already processes the session list on each refresh. Adding a `Set<String>` of unread IDs is O(n) with no extra queries. Views stay stateless.

### Complexity Assessment
**Low.** 5 files modified, 1 migration added. Follows existing patterns (DB migration, VM computed state, row view prop). No new abstractions. Low regression risk — unread is additive and doesn't change existing behavior. The only tricky part is ensuring the actionable-state filter is correct.

## Impact Analysis
- **New Files**: None
- **Modified Files**:
  - `Sources/SeshctlCore/Session.swift` — add `lastReadAt` field
  - `Sources/SeshctlCore/Database.swift` — add v4 migration, add `markSessionRead()` method
  - `Sources/SeshctlUI/SessionListViewModel.swift` — compute unread set, expose `markSessionRead()`
  - `Sources/SeshctlUI/SessionRowView.swift` — render "Unread" tag
  - `Sources/SeshctlApp/AppDelegate.swift` — call `markSessionRead()` in `focusSession()`
- **Dependencies**: None new. Uses existing GRDB, SwiftUI.
- **Similar Modules**: Focus memory (`rememberFocusedSession`) is conceptually related but serves a different purpose (selection restore vs. read tracking).

## Implementation Steps

### Step 1: Add `lastReadAt` to Session model
- [x] Add `public var lastReadAt: Date?` to `Session` struct in `Sources/SeshctlCore/Session.swift`
- [x] Add `case lastReadAt = "last_read_at"` to `CodingKeys`

### Step 2: Add DB migration and `markSessionRead()` method
- [x] Add `v4_add_last_read_at` migration to `Sources/SeshctlCore/Database.swift` — `ALTER TABLE sessions ADD COLUMN last_read_at DATETIME`
- [x] Add `markSessionRead(id: String)` method that sets `last_read_at = Date()` for the given session ID

### Step 3: Compute unread state in SessionListViewModel
- [x] Add `@Published public private(set) var unreadSessionIds: Set<String> = []` to `SessionListViewModel`
- [x] In `refresh()`, after fetching sessions, compute the unread set: sessions where `(lastReadAt == nil || updatedAt > lastReadAt)` AND `status` is in `{.idle, .completed, .canceled, .stale}`
- [x] Add `markSessionRead(_ session: Session)` method that calls `database.markSessionRead(id:)` and removes the ID from `unreadSessionIds`

### Step 4: Render "Unread" tag in SessionRowView
- [x] Add `var isUnread: Bool = false` property to `SessionRowView`
- [x] In the HStack after the tool badge text, conditionally show `Text("Unread")` styled as a small pill (monospaced caption2, accent color, rounded background)
- [x] Update `SessionListView` to pass `isUnread` from the view model's `unreadSessionIds`

### Step 5: Wire up mark-read in AppDelegate
- [x] In `focusSession()`, call `viewModel?.markSessionRead(session)` before dismissing the panel
- [x] Also mark read on tap in `SessionListView.onTapGesture` (mouse click to focus)

### Step 6: Write Tests
- [x] Add test in `DatabaseTests.swift`: `markSessionRead` sets `last_read_at` and persists
- [x] Add test in `DatabaseTests.swift`: new sessions have `nil` `lastReadAt`
- [x] Add test in `SessionListViewModelTests.swift`: unread set includes sessions with `updatedAt > lastReadAt` in actionable states
- [x] Add test in `SessionListViewModelTests.swift`: working/waiting sessions excluded from unread set
- [x] Add test in `SessionListViewModelTests.swift`: `markSessionRead` removes session from unread set
- [x] Add test in `SessionListViewModelTests.swift`: never-read session in idle state is unread
- [x] Add test in `SessionListViewModelTests.swift`: never-read session in working state is NOT unread

## Acceptance Criteria
- [ ] [test] Sessions in idle/completed/canceled/stale with `updatedAt > lastReadAt` show "Unread" tag
- [ ] [test] Sessions in working/waiting state never show "Unread" tag
- [ ] [test] Pressing Enter/e on a session clears its "Unread" tag
- [ ] [test] Brand new (never-focused) sessions show "Unread" when in actionable state
- [ ] [test-manual] "Unread" tag appears visually as a styled pill next to the tool badge
- [ ] [test-manual] Tag disappears on focus and reappears if session updates again

## Edge Cases
- **Session never focused + in working state**: Not unread (nothing to action). Becomes unread when it transitions to idle.
- **Session read, then updated, then goes working**: Not unread while working. Becomes unread when idle/completed.
- **App restart**: `lastReadAt` persists in DB — unread state survives restarts.
- **GC**: When old sessions are deleted, their `lastReadAt` is deleted too. No orphaned state.
- **Multiple rapid transitions**: Only the final resting state matters for unread. If a session rapidly goes working→idle→working→idle, it's unread at the idle checkpoints.
