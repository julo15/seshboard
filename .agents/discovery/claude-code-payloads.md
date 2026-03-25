# Claude Code Hook Payloads

Documented from official hook reference — no experimental capture needed.

## Common Fields (all events)

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory",
  "permission_mode": "default",
  "hook_event_name": "EventName"
}
```

## Relevant Events for Seshctl

### SessionStart
```json
{
  "source": "startup|resume|clear|compact",
  "model": "claude-sonnet-4-6"
}
```

### UserPromptSubmit
```json
{
  "prompt": "User's text prompt"
}
```

### Stop
```json
{
  "stop_hook_active": true,
  "last_assistant_message": "I've completed the refactoring..."
}
```

### SessionEnd
```json
{
  "reason": "clear|logout|prompt_input_exit|bypass_permissions_disabled|other"
}
```

### Notification
```json
{
  "message": "Claude needs your permission to use Bash",
  "title": "Permission needed",
  "notification_type": "permission_prompt|idle_prompt|auth_success|elicitation_dialog"
}
```

## Mapping to Seshctl

| Seshctl event | Claude Code hook | Key fields |
|---|---|---|
| Session start | `SessionStart` | `session_id`, `cwd` (from common fields) |
| User message → working | `UserPromptSubmit` | `prompt` → `last_ask` |
| LLM done → idle | `Stop` | (status change only) |
| Session end | `SessionEnd` | `reason` |

## Key Findings

- **`session_id`** is available on every event — use as `conversation_id`
- **`cwd`** is available on every event — use as `directory`
- **PID**: not in payload, but `$PPID` in shell gives the Claude Code process PID
- **`SessionStart` exists** — contrary to original plan assumption. No need to use Notification for first-contact detection
- **`UserPromptSubmit`** is better than `Notification` for capturing user messages — it has the actual prompt text
- **`Stop`** fires when Claude finishes — use for idle transition
- **`SessionEnd`** fires on exit — use for completed/canceled

## Hook Firing Behavior (empirically tested 2026-03-24)

### Tool call lifecycle

Every tool call fires `PreToolUse` before execution and `PostToolUse` after. This includes
internal tools like `AskUserQuestion`, not just user-visible ones like `Bash` or `Read`.

```
PreToolUse(Bash) → [command runs] → PostToolUse(Bash)
PreToolUse(AskUserQuestion) → [user answers] → PostToolUse(AskUserQuestion)
```

### When the user is asked a question (AskUserQuestion / permission prompts)

**Critical finding:** `UserPromptSubmit` does NOT fire when the user answers a question or
approves a permission prompt. It only fires for user-initiated messages typed into the prompt.

The actual sequence for AskUserQuestion:

```
PreToolUse(AskUserQuestion)           ← Claude is about to ask
NOTIFICATION (permission_prompt)      ← question is shown to user (may be delayed)
  ... user is thinking ...
PostToolUse(AskUserQuestion)          ← user has answered
PreToolUse(next tool)                 ← Claude resumes working
```

For permission prompts (tool approval):

```
PreToolUse(Bash)                      ← Claude wants to run a command
  ... user is prompted to approve ...
PostToolUse(Bash)                     ← user approved (or denied)
```

**Key observations:**

- `NOTIFICATION` fires for AskUserQuestion but NOT always for permission prompts.
  Quick approvals may complete before the notification timeout triggers.
- `NOTIFICATION` fires with `notification_type: "permission_prompt"` for both cases
  when it does fire.
- `PostToolUse` is the only reliable signal that the user has answered/approved.
- `PostToolUse` payload includes `tool_response` with the user's answer.
- There is NO hook that fires between "question shown" and "user answers" — the gap
  is invisible to hooks.

### Hook ordering and race conditions

Hooks fire asynchronously. The ordering between `Stop` and `Notification` is not guaranteed:

```
Scenario A (normal):    working → Notification(waiting) → Stop(idle)
Scenario B (race):      working → Stop(idle) → Notification(waiting)
```

With `PreToolUse` setting `working` before every tool call, `Notification` always sees
`working` state. The guard must only allow `waiting` from `working` — a late Notification
arriving after `Stop` (when state is `idle`) is stale and must be rejected, otherwise the
session gets stuck in blue.

### Detecting "user answered, Claude is working again"

`PreToolUse` is the most reliable hook for this. After a user answers a question, Claude
immediately makes a tool call, which fires `PreToolUse`. Using `PreToolUse` to set
`status=working` on every tool call ensures the waiting→working transition happens
as soon as Claude resumes.

To keep this cheap, use `--skip-git` to avoid git subprocess calls on status-only updates.

## Revised Hook Design

```
SessionStart     → seshctl-cli start --tool claude --dir $CWD --pid $PPID --conversation-id $SESSION_ID
UserPromptSubmit → seshctl-cli update --pid $PPID --tool claude --ask "$PROMPT" --status working
PreToolUse       → seshctl-cli update --pid $PPID --tool claude --status working --skip-git
Notification     → seshctl-cli update --pid $PPID --tool claude --status waiting
Stop             → seshctl-cli update --pid $PPID --tool claude --status idle
SessionEnd       → seshctl-cli end --pid $PPID --tool claude
```
