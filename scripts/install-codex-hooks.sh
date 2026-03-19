#!/bin/bash
# Install seshctl Codex hooks:
# 1. Copies hook scripts to ~/.local/share/seshctl/hooks/codex/
# 2. Upserts hook entries in ~/.agents/hooks.json
# 3. Ensures codex_hooks = true in ~/.agents/config.toml
# Idempotent — safe to run multiple times.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SOURCE="$REPO_DIR/hooks/codex"
HOOKS_DEST="$HOME/.local/share/seshctl/hooks/codex"
SETTINGS="$HOME/.agents/hooks.json"
CONFIG="$HOME/.agents/config.toml"

# --- 1. Copy hook scripts ---

mkdir -p "$HOOKS_DEST"
cp "$HOOKS_SOURCE"/*.sh "$HOOKS_DEST/"
chmod +x "$HOOKS_DEST"/*.sh
echo "copied hooks to $HOOKS_DEST"

# --- 2. Upsert hook entries in hooks.json ---

if ! command -v jq &>/dev/null; then
    echo "error: jq is required (brew install jq)"
    exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"

if [ ! -f "$SETTINGS" ]; then
    echo '{"hooks":{}}' > "$SETTINGS"
    echo "created $SETTINGS"
fi

# Define the hooks seshctl needs.
# Each line: EVENT_NAME|MATCHER|COMMAND
HOOK_DEFS=(
    "SessionStart||$HOOKS_DEST/session-start.sh"
    "UserPromptSubmit||$HOOKS_DEST/user-prompt.sh"
    "Stop||$HOOKS_DEST/stop.sh"
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
    echo "hooks.json updated"
else
    echo "hooks.json unchanged"
fi

rm -f "$tmp"

# --- 3. Ensure codex_hooks = true in config.toml ---

mkdir -p "$(dirname "$CONFIG")"

if [ ! -f "$CONFIG" ]; then
    printf '[features]\ncodex_hooks = true\n' > "$CONFIG"
    echo "created $CONFIG with codex_hooks = true"
elif grep -q 'codex_hooks = true' "$CONFIG"; then
    echo "config.toml already has codex_hooks = true"
else
    if grep -q '^\[features\]' "$CONFIG"; then
        # Append under existing [features] section
        sed -i '' '/^\[features\]/a\
codex_hooks = true' "$CONFIG"
    else
        # Append new [features] section
        printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG"
    fi
    echo "config.toml updated with codex_hooks = true"
fi

echo "done"
