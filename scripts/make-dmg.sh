#!/usr/bin/env bash
# Build a styled, drag-to-/Applications DMG from the signed Seshctl.app bundle.
#
# Inputs:  dist/Seshctl.app (must exist; build via `make bundle && make sign`)
# Outputs: dist/Seshctl-<VERSION>.dmg
#
# Notes:
#   - We do NOT pass a background image. We can add one later when we have art.
#   - `create-dmg` occasionally fails on the first run due to a Finder timing
#     bug; we retry once before giving up.
#   - The output DMG is a build artifact; if it already exists we recreate it
#     from scratch with `rm -f`.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

BUNDLE_DIR="${REPO_DIR}/dist/Seshctl.app"
INFO_PLIST="${REPO_DIR}/Resources/Info.plist"

# 1. Bundle exists?
if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "Error: ${BUNDLE_DIR} not found." >&2
  echo "  Run \`make bundle && make sign\` first." >&2
  exit 1
fi

# 2. create-dmg installed?
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

# 3. Read version from Info.plist (single source of truth for bundle metadata).
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${INFO_PLIST}")"
if [[ -z "${VERSION}" ]]; then
  echo "Error: could not read CFBundleShortVersionString from ${INFO_PLIST}" >&2
  exit 1
fi

DMG_PATH="${REPO_DIR}/dist/Seshctl-${VERSION}.dmg"

# 4. Output is a build artifact — fine to remove with rm -f.
if [[ -e "${DMG_PATH}" ]]; then
  echo "==> Removing existing ${DMG_PATH}"
  rm -f "${DMG_PATH}"
fi

# 5. Run create-dmg. Retry once on failure (Finder timing bug workaround).
run_create_dmg() {
  create-dmg \
    --volname "Seshctl ${VERSION}" \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "Seshctl.app" 140 180 \
    --app-drop-link 400 180 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${BUNDLE_DIR}"
}

attempt=1
max_attempts=2
while true; do
  echo "==> Building DMG (attempt ${attempt}/${max_attempts}) ..."
  if run_create_dmg; then
    break
  fi
  if (( attempt >= max_attempts )); then
    echo "Error: create-dmg failed after ${max_attempts} attempts." >&2
    exit 1
  fi
  echo "WARN: create-dmg failed; sleeping 3s and retrying ..." >&2
  sleep 3
  # Clean up partial artifact before retry.
  rm -f "${DMG_PATH}"
  attempt=$(( attempt + 1 ))
done

echo ""
echo "==> DMG built."
echo "    Bundle: ${BUNDLE_DIR}"
echo "    DMG:    ${DMG_PATH}"
DMG_SIZE="$(du -h "${DMG_PATH}" | cut -f1)"
echo "    Size:   ${DMG_SIZE}"
echo ""
echo "==> Verifying DMG ..."
hdiutil verify "${DMG_PATH}" | tail -3
