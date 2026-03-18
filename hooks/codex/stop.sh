#!/bin/bash
# Codex Stop hook → seshboard-cli update (idle)
# Fires when the agent finishes responding.
set -euo pipefail

seshboard-cli update \
  --pid "$PPID" \
  --tool codex \
  --status idle \
  > /dev/null 2>&1 &
