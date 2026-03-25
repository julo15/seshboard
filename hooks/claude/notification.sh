#!/bin/bash
# Claude Code Notification hook → seshctl-cli update (waiting)
# Fires when the agent needs user input.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
NOTIFICATION_TYPE=$(echo "$PAYLOAD" | jq -r '.notification_type // empty')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID NOTIFICATION $NOTIFICATION_TYPE" >> "$LOG_DIR/hooks.log"

seshctl-cli update \
  --pid "$PPID" \
  --tool claude \
  --status waiting \
  > /dev/null 2>&1 &
