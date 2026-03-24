#!/bin/bash
# Claude Code Stop hook → seshctl-cli update (idle)
# Fires when Claude finishes responding.
set -euo pipefail

PAYLOAD=$(cat)
REPLY=$(echo "$PAYLOAD" | jq -r '.last_assistant_message // empty')

ARGS=(--pid "$PPID" --tool claude --status idle)
if [ -n "$REPLY" ]; then
  ARGS+=(--reply "$REPLY")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1 &
