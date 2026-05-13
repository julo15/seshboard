#!/bin/bash
# Cursor beforeSubmitPrompt hook → seshctl-cli update (working)
# Reads JSON payload from stdin, extracts the user's prompt and session id.
#
# Workspace + host-app are passed on every event so the lazy-create branch
# in `seshctl-cli update` produces a focusable row when sessionStart was
# missed (e.g., the conversation pre-dated `make install`). The hook
# subprocess's CWD is /Users/<you>/.cursor, NOT the workspace — without an
# explicit --dir, lazy-create would fall back to that bogus path.
set -euo pipefail

PAYLOAD=$(cat)

IS_BG=$(echo "$PAYLOAD" | jq -r '.is_background_agent // false')
if [ "$IS_BG" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty')
WORKSPACE=$(echo "$PAYLOAD" | jq -r '.workspace_roots[0] // empty')
if [ -z "$WORKSPACE" ]; then
  WORKSPACE="${CURSOR_PROJECT_DIR:-}"
fi

ARGS=(--tool cursor --conversation-id "$SESSION_ID" --status working \
      --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor)
if [ -n "$WORKSPACE" ]; then
  ARGS+=(--dir "$WORKSPACE")
fi
if [ -n "$PROMPT" ]; then
  ARGS+=(--ask "$PROMPT")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1
