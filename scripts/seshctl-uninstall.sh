#!/bin/bash
# seshctl standalone uninstaller.
#
# This is a real file in ~/.local/bin/ (not a symlink into the bundle), so it
# survives even if the user drags Seshctl.app to the Trash. It performs the
# same cleanup as `FirstLaunchInstaller.uninstall()` but uses only `jq` + shell
# so it has no dependency on the bundle being present.
#
# What gets removed:
#   - seshctl-tagged hook entries from ~/.claude/settings.json
#   - seshctl-tagged hook entries from ~/.agents/hooks.json
#   - ~/.local/bin/seshctl, ~/.local/bin/seshctl-cli (only if symlinks)
#   - ~/.local/bin/seshctl-uninstall (this file itself)
#   - ~/.local/share/seshctl/hooks/  (NOT seshctl.db — that's user data)
#   - ~/Library/Application Support/Seshctl/
#
# What this does NOT touch:
#   - ~/.local/share/seshctl/seshctl.db (user data, kept like `make uninstall`)
#   - ~/.agents/config.toml `codex_hooks` flag (other tools may rely on it)
#   - /Applications/Seshctl.app (we'll log a reminder if it's still there)
#
# Idempotent: safe to run multiple times.

set -euo pipefail

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_HOOKS="$HOME/.agents/hooks.json"
HOOKS_DIR="$HOME/.local/share/seshctl/hooks"
BIN_DIR="$HOME/.local/bin"
SUPPORT_DIR="$HOME/Library/Application Support/Seshctl"
APP_BUNDLE="/Applications/Seshctl.app"

have_jq=1
if ! command -v jq >/dev/null 2>&1; then
    have_jq=0
    echo "warning: jq not found — falling back to a less robust JSON cleanup." >&2
fi

# Strip seshctl-tagged hook entries from a Claude/Codex settings file.
# A "seshctl-tagged" entry is one whose hooks[].command contains the substring
# "seshctl" anywhere — same matcher used by the Swift installer.
strip_seshctl_hooks() {
    local file="$1"
    [ -f "$file" ] || return 0

    if [ "$have_jq" -eq 1 ]; then
        local tmp
        tmp="$(mktemp)"
        if jq '
            if .hooks then
                .hooks |= with_entries(
                    .value |= map(select(
                        (.hooks // []) | map(.command // "") | map(test("seshctl")) | any | not
                    ))
                    | .value |= (if length == 0 then empty else . end)
                )
                | (if (.hooks | length) == 0 then del(.hooks) else . end)
            else . end
        ' "$file" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$file"
            echo "  cleaned $file"
        else
            rm -f "$tmp"
            echo "  warning: could not parse $file — left untouched" >&2
        fi
    else
        # Minimal fallback: just leave a backup and warn. We don't try to
        # hand-edit JSON without jq — too risky.
        cp "$file" "$file.seshctl-uninstall.bak"
        echo "  warning: leaving $file untouched (no jq); backup at $file.seshctl-uninstall.bak" >&2
    fi
}

echo "==> Removing seshctl hook entries from settings files"
strip_seshctl_hooks "$CLAUDE_SETTINGS"
strip_seshctl_hooks "$CODEX_HOOKS"

echo "==> Removing CLI symlinks from $BIN_DIR"
for link in "$BIN_DIR/seshctl" "$BIN_DIR/seshctl-cli"; do
    if [ -L "$link" ]; then
        rm -f "$link"
        echo "  removed symlink $link"
    elif [ -e "$link" ]; then
        echo "  skipping $link (real file, not a symlink — leaving it alone)"
    fi
done

echo "==> Removing hook scripts directory"
if [ -d "$HOOKS_DIR" ]; then
    rm -rf "$HOOKS_DIR"
    echo "  removed $HOOKS_DIR"
fi

echo "==> Removing application support directory"
if [ -d "$SUPPORT_DIR" ]; then
    rm -rf "$SUPPORT_DIR"
    echo "  removed $SUPPORT_DIR"
fi

if [ -e "$APP_BUNDLE" ]; then
    echo ""
    echo "Note: $APP_BUNDLE is still installed."
    echo "      Drag it to the Trash to complete the uninstall."
fi

# Self-delete last so the rest of the script always runs first.
SELF="$BIN_DIR/seshctl-uninstall"
if [ -f "$SELF" ]; then
    rm -f "$SELF"
fi

echo ""
echo "seshctl uninstalled."
