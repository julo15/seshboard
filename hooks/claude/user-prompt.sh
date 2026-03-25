#!/bin/bash
# Claude Code UserPromptSubmit hook → seshctl-cli update (working)
# Reads JSON payload from stdin, extracts the user's prompt.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID USER_PROMPT_SUBMIT" >> "$LOG_DIR/hooks.log"

ARGS=(--pid "$PPID" --tool claude --status working)
if [ -n "$PROMPT" ]; then
  ARGS+=(--ask "$PROMPT")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1 &
