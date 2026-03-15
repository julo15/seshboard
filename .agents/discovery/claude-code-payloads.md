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

## Relevant Events for Seshboard

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

## Mapping to Seshboard

| Seshboard event | Claude Code hook | Key fields |
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

## Revised Hook Design

```
SessionStart  → seshboard-cli start --tool claude --dir $CWD --pid $PPID --conversation-id $SESSION_ID
UserPromptSubmit → seshboard-cli update --pid $PPID --tool claude --ask "$PROMPT" --status working
Stop          → seshboard-cli update --pid $PPID --tool claude --status idle
SessionEnd    → seshboard-cli end --pid $PPID --tool claude
```

This is cleaner than the original plan — dedicated events instead of overloading Notification.
