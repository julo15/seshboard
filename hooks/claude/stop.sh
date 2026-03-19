#!/bin/bash
# Claude Code Stop hook → seshctl-cli update (idle)
# Fires when Claude finishes responding.
set -euo pipefail

seshctl-cli update \
  --pid "$PPID" \
  --tool claude \
  --status idle \
  > /dev/null 2>&1 &
