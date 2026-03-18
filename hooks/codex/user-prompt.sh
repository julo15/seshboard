#!/bin/bash
# Codex UserPromptSubmit hook → seshboard-cli update (working)
# Reads JSON payload from stdin, extracts the user's prompt.
set -euo pipefail

PAYLOAD=$(cat)
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty')

ARGS=(--pid "$PPID" --tool codex --status working)
if [ -n "$PROMPT" ]; then
  ARGS+=(--ask "$PROMPT")
fi

seshboard-cli update "${ARGS[@]}" > /dev/null 2>&1 &
