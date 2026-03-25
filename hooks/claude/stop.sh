#!/bin/bash
# Claude Code Stop hook → seshctl-cli update (idle)
# Fires when Claude finishes responding.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
REPLY=$(echo "$PAYLOAD" | jq -r '.last_assistant_message // empty')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID STOP" >> "$LOG_DIR/hooks.log"

ARGS=(--pid "$PPID" --tool claude --status idle)
if [ -n "$REPLY" ]; then
  ARGS+=(--reply "$REPLY")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1 &
