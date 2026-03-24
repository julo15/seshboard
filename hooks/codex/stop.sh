#!/bin/bash
# Codex Stop hook → seshctl-cli update (idle)
# Fires when the agent finishes responding.
set -euo pipefail

PAYLOAD=$(cat)
REPLY=$(echo "$PAYLOAD" | jq -r '.last_assistant_message // empty')

ARGS=(--pid "$PPID" --tool codex --status idle)
if [ -n "$REPLY" ]; then
  ARGS+=(--reply "$REPLY")
fi

seshctl-cli update "${ARGS[@]}" > /dev/null 2>&1
