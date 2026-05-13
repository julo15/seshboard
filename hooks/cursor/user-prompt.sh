#!/bin/bash
# Cursor beforeSubmitPrompt hook → seshctl-cli update (working)
# Reads JSON payload from stdin, extracts the user's prompt and session id.
set -euo pipefail

PAYLOAD=$(cat)

IS_BG=$(echo "$PAYLOAD" | jq -r '.is_background_agent // false')
if [ "$IS_BG" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty')

ARGS=(--tool cursor --conversation-id "$SESSION_ID" --status working)
if [ -n "$PROMPT" ]; then
  ARGS+=(--ask "$PROMPT")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1
