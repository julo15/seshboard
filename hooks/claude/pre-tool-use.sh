#!/bin/bash
# Claude Code PreToolUse hook → seshctl-cli update (working)
# Fires before each tool call, ensuring the session shows as working.
# Uses --skip-git to avoid expensive git subprocess calls.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID PRE_TOOL_USE $TOOL_NAME" >> "$LOG_DIR/hooks.log"

seshctl-cli update \
  --pid "$PPID" \
  --tool claude \
  --status working \
  --skip-git \
  > /dev/null 2>&1 &
