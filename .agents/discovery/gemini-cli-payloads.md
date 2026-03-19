# Gemini CLI Hook Payloads

Documented from official Gemini CLI docs / GitHub.

## Configuration

Hooks configured in `settings.json`:
- Project-level: `.gemini/settings.json`
- User-level: `~/.gemini/settings.json`

## Common Fields (all events)

```json
{
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "/current/working/directory",
  "hook_event_name": "EventName",
  "timestamp": "..."
}
```

Env vars also set: `GEMINI_PROJECT_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD`.

## Relevant Events for Seshctl

### SessionStart
Fires on session init, resume, or `/clear`.
```json
{
  "source": "..."
}
```

### BeforeAgent
Fires after user submits, before model plans. Has the user's prompt.
```json
{
  "prompt": "User's text prompt"
}
```

### AfterAgent
Fires after model generates final response.
```json
{
  "prompt": "...",
  "prompt_response": "...",
  "stop_hook_active": true
}
```

### SessionEnd
Fires on session exit or clear.
```json
{
  "reason": "..."
}
```

### Notification
System alerts.
```json
{
  "notification_type": "..."
}
```

## Mapping to Seshctl

| Seshctl event | Gemini CLI hook | Key fields |
|---|---|---|
| Session start | `SessionStart` | `session_id`, `cwd` |
| User message → working | `BeforeAgent` | `prompt` → `last_ask` |
| LLM done → idle | `AfterAgent` | (status change only) |
| Session end | `SessionEnd` | `reason` |

## Key Findings

- **`session_id`** available on every event — use as `conversation_id`
- **`cwd`** available on every event — use as `directory`
- **PID**: not in payload, use `$PPID` in shell
- **`BeforeAgent`** is the right hook for capturing user prompts (has `prompt` field)
- **`AfterAgent`** fires when model finishes — use for idle transition
- **`SessionStart`** and **`SessionEnd`** both exist — cleaner than original plan assumed

## Revised Hook Design

```
SessionStart  → seshctl-cli start --tool gemini --dir $CWD --pid $PPID --conversation-id $SESSION_ID
BeforeAgent   → seshctl-cli update --pid $PPID --tool gemini --ask "$PROMPT" --status working
AfterAgent    → seshctl-cli update --pid $PPID --tool gemini --status idle
SessionEnd    → seshctl-cli end --pid $PPID --tool gemini
```
