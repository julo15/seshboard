#!/bin/bash
# Claude Code SessionEnd hook → seshctl-cli end
# Fires when the session terminates.
set -euo pipefail

seshctl-cli end \
  --pid "$PPID" \
  --tool claude \
  > /dev/null 2>&1 &
