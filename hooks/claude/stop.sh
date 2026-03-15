#!/bin/bash
# Claude Code Stop hook → seshboard-cli update (idle)
# Fires when Claude finishes responding.
set -euo pipefail

seshboard-cli update \
  --pid "$PPID" \
  --tool claude \
  --status idle \
  > /dev/null 2>&1 &
