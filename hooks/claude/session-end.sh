#!/bin/bash
# Claude Code SessionEnd hook → seshboard-cli end
# Fires when the session terminates.
set -euo pipefail

seshboard-cli end \
  --pid "$PPID" \
  --tool claude \
  > /dev/null 2>&1 &
