#!/bin/bash
# Claude Code SessionStart hook → seshctl-cli start
# Reads JSON payload from stdin, extracts session_id, cwd, and transcript_path.
set -euo pipefail

PAYLOAD=$(cat)
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id')
CWD=$(echo "$PAYLOAD" | jq -r '.cwd')
TRANSCRIPT_PATH=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')

LOG_DIR="$HOME/.local/share/seshctl/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%S') $SESSION_ID SESSION_START" >> "$LOG_DIR/hooks.log"

ARGS=(--tool claude --dir "$CWD" --pid "$PPID" --conversation-id "$SESSION_ID")
if [ -n "$TRANSCRIPT_PATH" ]; then
  ARGS+=(--transcript-path "$TRANSCRIPT_PATH")
fi

# Capture Ghostty terminal ID if running inside Ghostty.
# The focused terminal at hook time is the one running this session.
if [ "${TERM_PROGRAM:-}" = "ghostty" ]; then
  GHOSTTY_ID=$(osascript -e '
    tell application "Ghostty"
      try
        set trm to focused terminal of selected tab of front window
        return id of trm
      end try
    end tell
  ' 2>/dev/null || true)
  if [ -n "$GHOSTTY_ID" ]; then
    ARGS+=(--window-id "$GHOSTTY_ID")
  fi
fi

seshctl-cli start "${ARGS[@]}" > /dev/null 2>&1 &
