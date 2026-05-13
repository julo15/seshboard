#!/bin/bash
# Cursor sessionEnd hook → seshctl-cli end
# Maps Cursor's `reason` enum onto our SessionStatus:
#   user_close | completed | window_close  → completed
#   aborted    | error                     → canceled
set -euo pipefail

PAYLOAD=$(cat)

IS_BG=$(echo "$PAYLOAD" | jq -r '.is_background_agent // false')
if [ "$IS_BG" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
REASON=$(echo "$PAYLOAD" | jq -r '.reason // empty')

case "$REASON" in
  aborted|error)
    STATUS=canceled
    ;;
  # Unknown / empty reasons (user_close, completed, window_close, and any future
  # enum values) default to completed.
  *)
    STATUS=completed
    ;;
esac

seshctl-cli end --tool cursor --conversation-id "$SESSION_ID" --status "$STATUS" \
  --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor > /dev/null 2>&1
