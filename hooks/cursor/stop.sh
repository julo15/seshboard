#!/bin/bash
# Cursor stop hook → seshctl-cli update (idle)
# Fires when the agent finishes its loop.
set -euo pipefail

PAYLOAD=$(cat)

IS_BG=$(echo "$PAYLOAD" | jq -r '.is_background_agent // false')
if [ "$IS_BG" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')

seshctl-cli update --tool cursor --conversation-id "$SESSION_ID" --status idle > /dev/null 2>&1
