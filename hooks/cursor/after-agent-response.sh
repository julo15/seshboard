#!/bin/bash
# Cursor afterAgentResponse hook → seshctl-cli update (reply + transcript_path)
# Reads JSON payload from stdin. `transcript_path` is non-null from this event
# onward; capture it so future transcript parsing has a pointer.
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
TEXT=$(echo "$PAYLOAD" | jq -r '.text // empty')
TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')
WORKSPACE=$(echo "$PAYLOAD" | jq -r '.workspace_roots[0] // empty')
if [ -z "$WORKSPACE" ]; then
  WORKSPACE="${CURSOR_PROJECT_DIR:-}"
fi
if [ -z "$WORKSPACE" ]; then
  exit 0
fi

ARGS=(--tool cursor --conversation-id "$SESSION_ID" \
      --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor)
if [ -n "$WORKSPACE" ]; then
  ARGS+=(--dir "$WORKSPACE")
fi
if [ -n "$TEXT" ]; then
  ARGS+=(--reply "$TEXT")
fi
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1
