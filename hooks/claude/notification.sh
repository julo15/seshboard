#!/bin/bash
# Claude Code Notification hook → seshboard-cli update (waiting)
# Fires when the agent needs user input.
set -euo pipefail

seshboard-cli update \
  --pid "$PPID" \
  --tool claude \
  --status waiting \
  > /dev/null 2>&1 &
