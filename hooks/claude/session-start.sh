#!/bin/bash
# Claude Code SessionStart hook → seshctl-cli start
# Reads JSON payload from stdin, extracts session_id and cwd.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
CWD=$(echo "$PAYLOAD" | jq -r '.cwd')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID SESSION_START" >> "$LOG_DIR/hooks.log"

seshctl-cli start \
  --tool claude \
  --dir "$CWD" \
  --pid "$PPID" \
  --conversation-id "$SESSION_ID" \
  > /dev/null 2>&1 &
