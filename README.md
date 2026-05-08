# Seshctl

A macOS session manager for terminal-based workflows. Tracks coding sessions across Terminal.app, iTerm2, and VS Code terminals, with a native menu bar app and CLI.

![Seshctl session panel](docs/screenshot.png)

## Requirements

- macOS 13+
- Swift 6.0+ (comes with Xcode 16+) — only needed if you build from source
- [jq](https://jqlang.github.io/jq/) (for `make install-hooks`)
- Optional: `create-dmg` and the GitHub CLI for cutting releases — see [`docs/release.md`](docs/release.md)

## Install

### Download (recommended)

Grab the latest `Seshctl.dmg` from the [releases page](https://github.com/julo15/seshctl/releases/latest), open it, and drag `Seshctl.app` to `/Applications`.

> **First launch:** because Seshctl is currently self-signed (not yet notarized), macOS Gatekeeper will say *"Seshctl can't be opened because it is from an unidentified developer."* Right-click the app → **Open** → confirm. Once approved, double-clicks work normally. (This goes away once we ship Stage 1B with a Developer ID — see [Roadmap](#roadmap).)

On first launch, Seshctl shows a one-screen welcome panel. Click **Install** and it will:

- Symlink `~/.local/bin/seshctl` → the bundled CLI
- Drop a standalone `~/.local/bin/seshctl-uninstall` cleanup script (survives bundle deletion)
- Register Claude Code hooks in `~/.claude/settings.json`
- Register Codex hooks in `~/.agents/hooks.json` (and set `codex_hooks = true` in `~/.agents/config.toml`)

All operations are idempotent and reversible.

#### VS Code extension

If you use VS Code (or Cursor / VS Code Insiders), install the companion extension so Seshctl can focus terminal tabs by PID:

```sh
make install-vscode
```

Reload VS Code after installing to activate the extension.

### Updating

For now: download a new DMG from the releases page and drag it over the existing `/Applications/Seshctl.app`. macOS keeps your TCC Automation grants because the code-signing identity stays the same. **Auto-updates are coming in Phase 2** (see [Roadmap](#roadmap)).

### Uninstalling

Three ways out, all idempotent:

- **Recommended (clean):** From a terminal, `seshctl uninstall --full`. Removes the CLI symlink, hook entries from both LLM configs, the standalone uninstaller, and the marker file. Then drag `Seshctl.app` from `/Applications` to Trash.
- **After-the-fact:** If you already trashed `Seshctl.app`, run `seshctl-uninstall` from a terminal. It's a real file in `~/.local/bin/` (not a symlink into the bundle), so it survives. Same cleanup as above.
- **Drag-to-trash and forget:** Hook scripts have a defensive guard that no-ops if `seshctl-cli` isn't on PATH. After 5 consecutive misses, hooks self-clean their own settings entries and remove `~/.local/share/seshctl/hooks`. The user data DB at `~/.local/share/seshctl/seshctl.db` stays — delete it manually if you don't want it.

### For developers (build from source)

```sh
git clone https://github.com/julo15/seshctl.git
cd seshctl
make install    # builds release + installs CLI + hooks + launches app (unsigned dev build)
```

`make install` is the dev iteration path: produces an unsigned raw executable in `~/.local/bin/seshctl-cli` and launches `SeshctlApp` in the background. Fast rebuild loop. **Don't use `make install` if you already have the DMG installed — they conflict over hook registrations.**

For producing a signed `.dmg` to share with others, see [`docs/release.md`](docs/release.md).

### LLM CLI hooks

Seshctl tracks session status through hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/hooks) and Codex. The DMG's first-launch installer (and `make install` for dev builds) registers these automatically. To manage hooks separately:

```sh
make install-hooks    # register hooks for Claude Code and Codex
make uninstall-hooks  # remove hooks for Claude Code and Codex
```

Hook scripts are installed to `~/.local/share/seshctl/hooks/{claude,codex}/` and registered in `~/.claude/settings.json` and `~/.agents/hooks.json` respectively. Both commands are idempotent.

## Usage

Press **Cmd+Shift+S** to toggle the session panel.

### Session list

- **j / k** or **Arrow keys** — navigate sessions
- **gg** — jump to top
- **G** — jump to bottom
- **Enter** — focus the selected session's terminal
- **f** — fork the selected Claude session into a new branched session in a new tab (then **y** to confirm, **n** to cancel)
- **o** — open session detail view
- **x** — kill session process (then **y** to confirm, **n** to cancel)
- **u** — mark the selected session as read (clears the "Unread" pill)
- **U** — mark all sessions as read (then **y** to confirm, **n** to cancel)
- **r** — cycle the source filter: all → local only → cloud only → all
- **v** — toggle list/tree view
- **h / l** — in tree mode, jump to previous/next group (h jumps to the current group's first session, then to the previous group)
- **/** — search/filter sessions
- **?** — open the keyboard help popover
- **q** or **Esc** — dismiss the panel

### Session detail

- **j / k** or **Arrow keys** — scroll line by line
- **gg** — jump to top
- **G** — jump to bottom
- **Ctrl+d / Ctrl+u** — half-page down/up
- **Ctrl+f / Ctrl+b** — full page down/up
- **q** or **Esc** — back to list

### Claude remote sessions

Seshctl can list Claude Code sessions hosted on claude.ai (Cowork) alongside local terminal sessions, and pair a local CLI with its claude.ai counterpart so Enter focuses the terminal. Until the in-app flow has built-in guidance, connecting requires a one-time manual step.

**Connecting to claude.ai**

1. Open the session panel (**Cmd+Shift+S**) and click the **⋯** button in the header (or press **Cmd+,**) to open Settings.
2. Click **Connect…**. A sign-in window opens on `claude.ai/login`.
3. **Sign in with email, not Google.** Google's "Continue with Google" flow is blocked inside embedded WebViews, so the sheet rejects it. Enter your email to request a magic link.
4. Open the magic-link email in your mail client. The link is set to open in your default browser, so clicking it won't complete sign-in inside the sheet. Instead, **right-click the link → Copy Link Address**.
5. Paste the URL into the **Paste magic-link URL** field at the top of the sign-in window and press Enter (or click **Go**). The sheet navigates to the URL, completes auth, and auto-dismisses on success.

Once connected, remote sessions appear in the panel with a cloud glyph. The connection persists until the claude.ai session cookie expires (~28 days) or you click **Disconnect** in Settings.

**Accounts that only have Google sign-in:** add an email/password or passkey on claude.ai's account settings first, then use that method in the sheet.

## Compatibility

### LLM tools

| Tool | Hooks | Transcript parsing | Notes |
|------|-------|--------------------|-------|
| Claude Code | Full | Full | All hook events, full transcript support. Sessions bridged to claude.ai (via `/remote-control`) show as a single row with a cloud glyph on line 2; Enter focuses the terminal. |
| Codex | Partial | Full | `SessionStart` hook doesn't fire until the first message is sent. No `UserPromptSubmit` (sessions never show "In Progress"). No `SessionEnd` hook — sessions close on `Stop` only. Requires `codex_hooks = true` feature flag (set automatically by `make install-hooks`) |
| Gemini | None | None | Tracked via CLI only (`seshctl-cli start --tool gemini`), no auto-hooks or transcript parsing yet |

### Terminal apps

| App | Focusing | Notes |
|-----|----------|-------|
| Terminal.app | Full | TTY-based tab matching via AppleScript |
| VS Code | Full | Requires the [companion extension](#vs-code-extension) for terminal tab focusing |
| iTerm2 | Implemented | TTY-based tab matching via AppleScript, not extensively tested |
| Ghostty | Full | Working-directory matching via native AppleScript API; resume via surface configuration |
| Warp | Full | DB-assisted tab matching via Warp's internal SQLite; resume via keystroke simulation. No split pane support yet |
| cmux | Full | AppleScript focus across cmux's two-level hierarchy (workspace = sdef `tab`, horizontal tab within = sdef `terminal`). `$CMUX_WORKSPACE_ID` and `$CMUX_SURFACE_ID` are captured by the session-start hook and packed into `windowId` as `"<workspace>\|<surface>"`; focus matches `id of tab` for the workspace, then `focus`es the matching `terminal` so both levels are raised. AppleScript resume via `new tab` + `input text`. **Fork** uses cmux's bundled CLI (`tree --json` → `new-surface` → `send`) to land a sibling tab in the same pane — see [cmux setup](#cmux-setup) for the required automation-mode opt-in |
| Conductor.build | None | No focus support — Conductor exposes no AppleScript dictionary, URI handler, or extension API for targeting a specific terminal pane. Implementing focus requires an integration point from Conductor |
| Other | Basic | Falls back to window-name matching via System Events |

The first time seshctl focuses a session in an AppleScript-driven terminal (Terminal.app, iTerm2, Ghostty, Warp, or cmux) or browser (Chrome, Arc, Safari), macOS will prompt you to grant Seshctl Automation permission for that target. **Once granted, the permission persists across rebuilds and updates** — Seshctl ships with a stable code-signing identity, so TCC caches each grant by signature. You can review or revoke these grants in System Settings → Privacy & Security → Automation.

On first launch, SeshctlApp also requests **Accessibility** permission (System Settings → Privacy & Security → Accessibility) — separate from Automation. This is used when flipping to a remote Claude session that lives in a non-frontmost Arc window: Arc's AppleScript dictionary doesn't expose any "raise this window" verb, so seshctl falls back to System Events' `AXRaise` to bring the matched window forward. Without the grant, the right tab still gets selected, but the wrong Arc window may stay visually on top.

#### cmux setup

cmux's fork-into-the-existing-workspace path drives cmux's bundled CLI (`/Applications/cmux.app/Contents/Resources/bin/cmux`) over its Unix socket. By default cmux gates that socket with `socketControlMode: "cmuxOnly"` — only descendants of the cmux GUI process can connect, which excludes SeshctlApp when launched from the Dock, `make install`, or a LaunchAgent. With the default mode, fork silently falls through to creating a new workspace.

To enable in-pane fork, opt cmux into a permissive socket mode by editing `~/.config/cmux/cmux.json`:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json",
  "schemaVersion": 1,

  "automation": {
    "socketControlMode": "automation"
  }
}
```

Then restart cmux (quit and relaunch). `automation` keeps the socket file at `0600` (only your user account can connect) but disables the process-ancestry check, which is the recommended choice for SeshctlApp. `allowAll` also works — it additionally `chmod`s the socket to `0666`, which any local process running as your user can then connect to; only choose this if you understand the trade.

Verify the change took effect:

```sh
ls -la ~/Library/Application\ Support/cmux/cmux.sock
# expect: srw------- (automation) or srw-rw-rw- (allowAll)
env -i HOME=$HOME PATH=$PATH /Applications/cmux.app/Contents/Resources/bin/cmux ping
# expect: PONG
```

If `cmux ping` returns `Failed to write to socket (Broken pipe, errno 32)`, the config didn't take effect — double-check that `cmux.json` parsed cleanly (it's JSONC, but malformed JSON is silently rejected) and that you restarted cmux after editing it.

### Browsers

Seshctl can focus an existing tab for a remote Claude Code session in these browsers; if no browser has the tab open, it falls back to the user's default browser.

| Browser | Focus existing tab | Notes |
| --- | --- | --- |
| Chrome (Google Chrome) | ✅ | macOS AppleScript dictionary |
| Arc | ✅ | Walks spaces; Little Arc popovers and archived spaces are skipped silently. Multi-window focus uses System Events `AXRaise` (requires Accessibility permission, prompted on first launch) — without the grant the matched tab is selected but the wrong window may stay frontmost |
| Safari | ✅ | macOS AppleScript dictionary |

When you flip between remote sessions in seshctl, the existing tab opened by seshctl is reused (its URL is set to the new session) instead of accumulating one tab per session. The tab is identified by the URL we last set on it (matched as the `/code/session_<id>` substring), so it survives Arc's Little-Arc → main-window promotion and is portable across all three browsers. A trade-off: if you manually open a tab at the same Claude session URL we tracked, our flip might navigate yours instead of ours.

## Roadmap

These deferred phases are tracked in [`.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md`](.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md) under "Future Phases":

| Phase | What | Status / Tracking |
|---|---|---|
| **1B — Developer ID + notarization** | Drop the right-click-to-Open ritual on first install. One-time TCC re-prompt expected. | Tracking: `<LIN-ID>` (or "TODO — file ticket") |
| **2 — Sparkle auto-updates** | Silent background updates. Replaces the current "Slack Jason a new DMG" workflow. | Tracking: `<LIN-ID>` (or "TODO — file ticket") |
| **3 — GitHub Actions CI release** | `git tag v0.x.y && git push --tags` produces a complete release with no manual steps. Only worth it once release cadence justifies it. | Tracking: `<LIN-ID>` (or "TODO — file ticket") |

Each phase has explicit triggers, first concrete steps, acceptance criteria, and risks documented in the plan file.

## Development

```sh
make build          # debug build
make test           # run all tests
make run-app        # run menu bar app (debug)
make run-cli ARGS="list"  # run CLI with arguments
make help           # see all available commands
```
