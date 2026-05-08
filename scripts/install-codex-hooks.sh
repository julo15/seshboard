#!/bin/bash
# Delegated to seshctl-cli. The bash logic that used to live here moved into
# Sources/SeshctlCore/FirstLaunchInstaller.swift. Kept as a thin shim so the
# Makefile / external callers still work.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="${REPO_DIR}/.build/release/seshctl-cli"
if [ ! -x "$CLI" ]; then
    CLI="$(command -v seshctl-cli || true)"
fi
if [ -z "$CLI" ] || [ ! -x "$CLI" ]; then
    echo "error: seshctl-cli not found. Run 'make build-release' or install via DMG first." >&2
    exit 1
fi

exec "$CLI" install --codex
