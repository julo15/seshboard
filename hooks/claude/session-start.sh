#!/bin/bash
# Claude Code SessionStart hook → seshctl-cli start
# Reads JSON payload from stdin, extracts session_id and cwd.
set -euo pipefail

PAYLOAD=$(cat)
CWD=$(echo "$PAYLOAD" | jq -r '.cwd')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')

seshctl-cli start \
  --tool claude \
  --dir "$CWD" \
  --pid "$PPID" \
  --conversation-id "$SESSION_ID" \
  > /dev/null 2>&1 &
