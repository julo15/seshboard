#!/bin/bash
# Cursor sessionStart hook → seshctl-cli start
# Reads JSON payload from stdin, extracts session_id and workspace root.
#
# Cursor 1.7+ fires this on new conversation creation. The `session_id` and
# `conversation_id` fields carry the same UUID; we key on it via
# --conversation-id because PPID is not stable across Cursor hook events
# (each event is a fresh /bin/zsh -c subprocess).
#
# We deliberately do NOT pass --pid here. Cursor's hook subprocess PPIDs are
# not stable across events and can coincidentally collide across distinct
# conversations over a long Cursor lifetime; keying start on PPID would let
# a new conversation's start hook mark an unrelated live conversation's row
# as completed. Conversation-id keying isolates each row.
#
# Host-app is passed explicitly because, without --pid, `Start.run` cannot
# auto-detect from the process tree. The update-style hooks pass these
# unconditionally and we mirror that here so every Cursor row ends up
# focusable.
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

ARGS=(--tool cursor --dir "$WORKSPACE" --conversation-id "$SESSION_ID" \
      --host-app-bundle-id com.todesktop.230313mzl4w4u92 --host-app-name Cursor)
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi

seshctl-cli start "${ARGS[@]}" > /dev/null 2>&1
