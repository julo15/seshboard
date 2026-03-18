#!/bin/bash
# Codex UserPromptSubmit hook → seshboard-cli update (working)
# Reads JSON payload from stdin, extracts the user's prompt and session metadata.
set -euo pipefail

PAYLOAD=$(cat)
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')
CWD=$(echo "$PAYLOAD" | jq -r '.cwd // empty')

ARGS=(--pid "$PPID" --tool codex --status working)
if [ -n "$PROMPT" ]; then
  ARGS+=(--ask "$PROMPT")
fi
if [ -n "$SESSION_ID" ]; then
  ARGS+=(--conversation-id "$SESSION_ID")
fi
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi
if [ -n "$CWD" ]; then
  ARGS+=(--dir "$CWD")
fi

seshboard-cli update "${ARGS[@]}" > /dev/null 2>&1 &
