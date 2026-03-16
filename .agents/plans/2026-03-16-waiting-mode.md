# Add `waiting` Status to Seshboard

**Date:** 2026-03-16
**Branch:** `julo/waiting-status`

## Background

When Claude Code calls `AskUserQuestion`, the agent is blocked waiting for user input. Currently this shows as `working` (orange pulsing dot), which is misleading — the user needs to act, not wait. A distinct `waiting` status makes it immediately obvious which sessions need attention.

## Changes

### 1. Add `waiting` case to `SessionStatus` enum

**File:** `Sources/SeshboardCore/Session.swift`

- Add `case waiting` to the `SessionStatus` enum (after `working`, before `completed`).
- Update `isActive` computed property to include `.waiting`:
  ```swift
  public var isActive: Bool {
      status == .idle || status == .working || status == .waiting
  }
  ```

### 2. Use existing Notification hook (not PreToolUse)

**File:** `hooks/claude/notification.sh` (new)

The Claude Code `Notification` event fires whenever the agent needs user input — this covers `AskUserQuestion`, permission prompts, tool denials, and any other blocking prompt. This is better than a `PreToolUse` hook on `AskUserQuestion` because:

- **Broader coverage** — catches all "needs input" moments, not just one tool.
- **Correct semantic** — `Notification` means "the agent can't proceed without the user," which is exactly what `waiting` means.
- **Simpler** — no need to parse JSON payloads or check tool names.

The script should call:
```bash
seshboard-cli update --pid "$PPID" --tool claude --status waiting > /dev/null 2>&1 &
```

Follow the same structure as the existing hooks (`set -euo pipefail`, backgrounded CLI call, header comment).

There is already a `Notification` hook in `~/.claude/settings.json` that posts to Slack. The seshboard hook should be added as a second entry in the `Notification` hooks array so both fire.

### 3. Transition back to `working`

No new work needed. The existing `hooks/claude/user-prompt.sh` (UserPromptSubmit hook) already sets `--status working` on every user prompt, which naturally handles the `waiting -> working` transition when the user answers the question.

Similarly, `hooks/claude/stop.sh` (Stop hook) sets `--status idle`, handling the case where the session ends while in `waiting`.

### 4. UI: blue dot with blink animation

**File:** `Sources/SeshboardUI/SessionRowView.swift`

**Color:** Add `.waiting: return .blue` to the `statusColor` computed property.

**Animation:** Use a steady on/off blink (distinct from the pulsing ring used by `working`):

- Add a new `@State private var isBlinking = false` property.
- Add a computed `isWaiting` property: `session.status == .waiting`.
- For the `waiting` status, apply an opacity toggle on the inner 8pt dot:
  ```swift
  .opacity(isWaiting ? (isBlinking ? 1.0 : 0.3) : 1.0)
  ```
- Use a `linear` timing curve with ~0.6s duration to get a crisp blink (not the easeInOut used by working):
  ```swift
  withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: true)) {
      isBlinking = true
  }
  ```
- No expanding rings for `waiting` — just the single dot blinking. This keeps it visually distinct from the `working` pulse/ring effect.
- Update the `.onChange(of: session.status)` handler to start/stop `isBlinking` alongside the existing `isPulsing` logic.

### 5. Database layer

No migration needed. The `status` column is a TEXT field storing the raw enum string. Adding a new enum case (`"waiting"`) works without schema changes. GRDB's `DatabaseValueConvertible` conformance via `RawRepresentable` handles it automatically.

### 6. CLI

**File:** `Sources/SeshboardCLI/` (the `update` command)

No changes expected — the CLI already accepts `--status <value>` and passes the string through. Verify that the status argument is parsed via the enum (or raw string) and that `waiting` is accepted after the enum change in step 1. If there is any validation/allow-list, add `waiting` to it.

### 7. Tests

**File:** `Tests/SeshboardCoreTests/DatabaseTests.swift`

Add the following tests:

- **`waiting` is a valid status:** Create a session, update it to `waiting`, read it back, assert `status == .waiting`.
- **`waiting` counts as active:** Create a session with `waiting` status, assert `session.isActive == true`.
- **`waiting` in active sessions list:** Create sessions with various statuses, call `listActiveSessions()` (or equivalent), assert that `waiting` sessions are included alongside `idle` and `working`.

**File:** `Tests/SeshboardUITests/` (if snapshot/unit tests exist for row view)

- Verify that `statusColor` returns `.blue` for `.waiting`.

### 8. Hook registration

Add the new `notification.sh` script as a second entry in the existing `Notification` hook array in `~/.claude/settings.json`:

```json
"Notification": [
  {
    "hooks": [
      {
        "command": "curl -X POST ...",
        "type": "command"
      }
    ],
    "matcher": ""
  },
  {
    "hooks": [
      {
        "command": "/path/to/seshboard/hooks/claude/notification.sh",
        "type": "command"
      }
    ],
    "matcher": ""
  }
]
```

This keeps the existing Slack notification alongside the new seshboard status update.

## Out of scope

- macOS notifications (tabled for later)
- Hooks for Gemini or Codex (can be added in a follow-up)
- Any other tool-specific waiting states (e.g., `Bash` waiting for user confirmation)

## Prerequisite

`SLACK_USER_ID` must be set in the shell environment for the existing Slack notification hook to work. This regressed during a dotfiles refactor — ensure it's exported in the shell profile before testing.
