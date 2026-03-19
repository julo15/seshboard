# Codex CLI Hook Payloads

Documented from Codex CLI GitHub repo and PR history.

## Configuration

Hooks configured in `hooks.json`:
- Project-level: `.codex/hooks.json`
- User-level: `~/.codex/hooks.json`

## Common Fields (all events)

```json
{
  "hook_event_name": "EventName",
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "/current/working/directory",
  "model": "o3",
  "permission_mode": "default"
}
```

## Supported Events

Codex CLI only ships **two** file-based hook events:

### SessionStart
Fires once at session beginning (startup, resume, or clear).
```json
{
  "source": "startup|resume|clear"
}
```

### Stop
Fires when the agent finishes a turn / session ends.
```json
{
  "stop_hook_active": true,
  "last_assistant_message": "..."
}
```

**Note:** `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, and `Notification` are defined in types but never wired up. Only `SessionStart` and `Stop` actually fire.

## Mapping to Seshctl

| Seshctl event | Codex CLI hook | Key fields |
|---|---|---|
| Session start | `SessionStart` | `session_id`, `cwd` |
| User message → working | *(not available)* | — |
| LLM done → idle | `Stop` | `last_assistant_message` |
| Session end | `Stop` | (same event) |

## Key Findings

- **Very limited hook surface** — only 2 events fire
- **No user prompt capture** — no `UserPromptSubmit` hook wired up, so `last_ask` won't be populated for Codex sessions
- **No separate session end** — `Stop` fires on every turn completion AND on session end. Can't distinguish "turn done" from "session over"
- **`session_id`** and **`cwd`** are available — core addressing works
- **PID**: not in payload, use `$PPID` in shell

## Revised Hook Design

```
SessionStart  → seshctl-cli start --tool codex --dir $CWD --pid $PPID --conversation-id $SESSION_ID
Stop          → seshctl-cli update --pid $PPID --tool codex --status idle
```

Limitations:
- No `last_ask` capture (no prompt hook)
- Can't detect true session end vs turn end — rely on `gc` to reap stale sessions when PID dies
