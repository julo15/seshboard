#!/bin/bash
# Claude Code PreToolUse hook → seshctl-cli update (working)
# Fires before each tool call, ensuring the session shows as working.
set -euo pipefail

seshctl-cli update \
  --pid "$PPID" \
  --tool claude \
  --status working \
  > /dev/null 2>&1 &
