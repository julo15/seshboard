#!/bin/bash
# Codex Stop hook → seshctl-cli update (idle)
# Fires when the agent finishes responding.
set -euo pipefail

seshctl-cli update \
  --pid "$PPID" \
  --tool codex \
  --status idle \
  > /dev/null 2>&1
