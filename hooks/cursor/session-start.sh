#!/bin/bash
# Cursor sessionStart hook → seshctl-cli start
# Reads JSON payload from stdin, extracts session_id and workspace root.
#
# Cursor 1.7+ fires this on new conversation creation. The `session_id` and
# `conversation_id` fields carry the same UUID; we key on it via
# --conversation-id because PPID is not stable across Cursor hook events
# (each event is a fresh /bin/zsh -c subprocess).
#
# Host-app is passed explicitly even though `seshctl-cli start` auto-detects
# from PPID. Cursor's hook subprocess runs under a helper-process ancestry
# that PID-walk detection may not resolve to the Cursor.app bundle; the
# update-style hooks pass these unconditionally, and we mirror that here so
# every Cursor row ends up focusable. Explicit params override auto-detect
# in `Start.run`.
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
TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')

ARGS=(--tool cursor --dir "$WORKSPACE" --pid "$PPID" --conversation-id "$SESSION_ID" \
      --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor)
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi

seshctl-cli start "${ARGS[@]}" > /dev/null 2>&1
