#!/bin/bash
# Codex SessionStart hook → seshboard-cli start
# Reads JSON payload from stdin, extracts session_id, cwd, and transcript_path.
set -euo pipefail

PAYLOAD=$(cat)
CWD=$(echo "$PAYLOAD" | jq -r '.cwd')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')

ARGS=(--tool codex --dir "$CWD" --pid "$PPID" --conversation-id "$SESSION_ID")
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi

seshboard-cli start "${ARGS[@]}" > /dev/null 2>&1
