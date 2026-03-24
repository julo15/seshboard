#!/bin/bash
# Claude Code PreToolUse hook → seshctl-cli update (working)
# Fires before each tool call, ensuring the session shows as working.
# Uses --skip-git to avoid expensive git subprocess calls.
set -euo pipefail

seshctl-cli update \
  --pid "$PPID" \
  --tool claude \
  --status working \
  --skip-git \
  > /dev/null 2>&1 &
