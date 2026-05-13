#!/bin/bash
# Cursor stop hook → seshctl-cli update (idle)
# Fires when the agent finishes its loop.
#
# Workspace + host-app are passed on every event so the lazy-create branch in
# `seshctl-cli update` produces a focusable row when sessionStart was missed.
set -euo pipefail

PAYLOAD=$(cat)

IS_BG=$(echo "$PAYLOAD" | jq -r '.is_background_agent // false')
if [ "$IS_BG" = "true" ]; then
  exit 0
fi

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
WORKSPACE=$(echo "$PAYLOAD" | jq -r '.workspace_roots[0] // empty')
if [ -z "$WORKSPACE" ]; then
  WORKSPACE="${CURSOR_PROJECT_DIR:-}"
fi
if [ -z "$WORKSPACE" ]; then
  exit 0
fi

ARGS=(--tool cursor --conversation-id "$SESSION_ID" --status idle \
      --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor)
if [ -n "$WORKSPACE" ]; then
  ARGS+=(--dir "$WORKSPACE")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1
