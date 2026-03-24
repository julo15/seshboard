#!/bin/bash
# Install seshctl Claude Code hooks:
# 1. Copies hook scripts to ~/.local/share/seshctl/hooks/
# 2. Upserts hook entries in ~/.claude/settings.json
# Idempotent — safe to run multiple times.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SOURCE="$REPO_DIR/hooks/claude"
HOOKS_DEST="$HOME/.local/share/seshctl/hooks/claude"
SETTINGS="$HOME/.claude/settings.json"

# --- 1. Copy hook scripts ---

mkdir -p "$HOOKS_DEST"
cp "$HOOKS_SOURCE"/*.sh "$HOOKS_DEST/"
chmod +x "$HOOKS_DEST"/*.sh
echo "copied hooks to $HOOKS_DEST"

# --- 2. Upsert hook entries in settings.json ---

if [ ! -f "$SETTINGS" ]; then
    echo "error: $SETTINGS not found"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "error: jq is required (brew install jq)"
    exit 1
fi

# Define the hooks seshctl needs.
# Each line: EVENT_NAME|MATCHER|COMMAND
HOOK_DEFS=(
    "SessionStart||$HOOKS_DEST/session-start.sh"
    "SessionEnd||$HOOKS_DEST/session-end.sh"
    "UserPromptSubmit||$HOOKS_DEST/user-prompt.sh"
    "Stop||$HOOKS_DEST/stop.sh"
    "Notification||$HOOKS_DEST/notification.sh"
)

backup="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$backup"
echo "backed up settings to $backup"

tmp=$(mktemp)
cp "$SETTINGS" "$tmp"

for def in "${HOOK_DEFS[@]}"; do
    IFS='|' read -r event matcher command <<< "$def"

    # Check if this exact command already exists in the event's hook array
    exists=$(jq --arg event "$event" --arg cmd "$command" '
        (.hooks[$event] // [])
        | map(select(.hooks[]?.command == $cmd))
        | length > 0
    ' "$tmp")

    if [ "$exists" = "true" ]; then
        echo "  $event: already registered"
        continue
    fi

    # Remove any old seshctl hook for this event, then add the current one
    jq --arg event "$event" --arg cmd "$command" --arg matcher "$matcher" '
        .hooks[$event] = (
            [(.hooks[$event] // [])[] | select(.hooks[]?.command | test("seshctl") | not)]
        ) + [
            {
                "hooks": [{"command": $cmd, "type": "command"}],
                "matcher": $matcher
            }
        ]
    ' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"

    echo "  $event: registered"
done

# Write back only if changed
if ! diff -q "$SETTINGS" "$tmp" &>/dev/null; then
    cp "$tmp" "$SETTINGS"
    echo "settings.json updated"
else
    echo "settings.json unchanged"
fi

rm -f "$tmp"

# --- 3. Install Codex hooks ---
"$REPO_DIR/scripts/install-codex-hooks.sh"

echo "done"
