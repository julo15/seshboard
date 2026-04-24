# Seshctl

## Build & Test

- **SwiftPM lock contention:** SwiftPM acquires a file lock on `.build/`. If a second `swift build` or `swift test` runs concurrently, it blocks indefinitely. Always use a **timeout of 120s** for builds and **30s** for test runs. If a build/test hangs or times out, immediately run `make kill-build` before retrying.
- `make kill-build` — force-kills all stale SwiftPM processes
- `make install` — build release + install CLI + hooks + restart app (full deploy)
- `make install-cli` — build release + install CLI to ~/.local/bin
- `make install-app` — build release + restart SeshctlApp
- `make install-hooks` — register Claude Code and Codex hooks in ~/.claude/settings.json and ~/.agents/hooks.json
  - **Codex hooks require a feature flag:** `codex_hooks = true` must be set in `~/.agents/config.toml`. The install script enables this automatically.
- `make uninstall` — stop app + remove CLI + unregister hooks
- `make uninstall-cli` — remove CLI from ~/.local/bin
- `make uninstall-app` — stop SeshctlApp
- `make uninstall-hooks` — remove Claude Code and Codex hooks
- `make test` — run all tests

## Test Coverage

When adding or modifying logic in `Sources/`, run tests with coverage and verify your changes are covered:

```bash
swift test --enable-code-coverage   # ~7s, outputs coverage JSON
swift test --show-codecov-path      # prints path to the JSON
```

Extract coverage for project files (not dependencies) with:
```bash
jq '[.data[0].files[] | select(.filename | contains("/Sources/")) | {file: (.filename | split("/Sources/")[1]), pct: (.summary.lines.percent * 100 | round / 100)}]' "$(swift test --show-codecov-path)"
```

**Rules:**
- New logic (view models, database methods, parsers) must have tests. View-only files (SwiftUI views) are exempt.
- If you add a public method to a file that already has tests, add a test for the new method.
- Check coverage of files you modified — if a file drops below 60% line coverage after your changes, add tests to bring it back up.

## Adding Terminal App Support

Seshctl supports multiple terminal apps. The architecture enforces a single code path for all session actions (focus, resume, clipboard fallback) through three key files:

- **`Sources/SeshctlCore/TerminalApp.swift`** — Registry enum. Single source of truth for bundle IDs, display names, URI schemes, and capabilities. Every `switch` is exhaustive (no `default` cases) — adding a new case triggers compiler errors everywhere it needs handling.
- **`Sources/SeshctlUI/TerminalController.swift`** — Execution engine. Handles both focusing existing tabs and resuming sessions in new tabs. All terminal interaction goes through here.
- **`Sources/SeshctlUI/SessionAction.swift`** — Routing entry point. All user actions (Enter on any row type) go through `SessionAction.execute()`. Never add focus/resume logic to AppDelegate or views.

### How detection works

When `seshctl-cli start` runs, `detectHostApp()` in `Sources/seshctl-cli/SeshctlCLI.swift` walks the process tree from the shell PID upward, looking for a GUI app via `NSRunningApplication`. The bundle ID and name are stored in the database alongside the session. No per-app code is needed here — any app that launches a shell process is detected automatically.

One edge case: cmux embeds libghostty and sets `TERM_PROGRAM=ghostty` in the shells it spawns, so matching on `TERM_PROGRAM` alone would misroute cmux sessions to Ghostty. `TerminalApp.from(environment:)` handles this by checking `$CMUX_WORKSPACE_ID` / `$CMUX_SOCKET_PATH` first and only falling back to `TERM_PROGRAM` when neither is present.

### How focusing and resuming works

When the user presses Enter on any row, `SessionAction.execute()` determines the action (focus vs resume), resolves the target app via a single chain (DB → PID walk → frontmost terminal), and dispatches to `TerminalController`.

**Pattern 1: AppleScript focus** (Terminal.app, iTerm2, Ghostty, Warp, cmux) — `supportsAppleScriptFocus` capability

`open -b` brings the app forward, then AppleScript iterates windows/tabs matching by TTY path (Terminal.app, iTerm2), terminal ID/working directory (Ghostty), DB-assisted tab matching (Warp), or workspace + surface UUIDs (cmux — `$CMUX_WORKSPACE_ID` and `$CMUX_SURFACE_ID` are captured by the session-start hook and packed into `windowId` as `"<workspace>|<surface>"`). For cmux, the outer loop matches `id of tab` against the workspace UUID and a nested loop then `focus`es the `terminal` whose `id` matches the surface UUID, so both levels of cmux's hierarchy (vertical workspace list, horizontal tab within) are raised.

**Pattern 2: URI handler** (VS Code, VS Code Insiders, Cursor) — `supportsURIHandler` capability

`open -b` brings the app forward, then a URI handler (e.g. `vscode://julo15.seshctl/focus-terminal?pid=<pid>`) triggers the companion extension.

**Pattern 3: Generic AppleScript fallback** (unknown apps)

System Events script searches window names for the session's directory name and raises the matching window.

### How to add a new terminal app

1. **Add a case to the `TerminalApp` enum** in `TerminalApp.swift` — the compiler will show you every place that needs a handler (bundle ID, display name, URI scheme, capabilities)
2. **Add focus/resume AppleScript** in `TerminalController.buildFocusScript()` and/or `buildResumeScript()` if the app uses AppleScript
3. **Add tests** in `Tests/SeshctlUITests/TerminalControllerTests.swift` for script generation and focus routing
4. **Build a companion extension** (only if using the URI handler pattern)

**Rules:**
- All bundle IDs and URI schemes live in `TerminalApp` — never hardcode them elsewhere
- All user actions go through `SessionAction.execute()` — never add focus/resume logic to AppDelegate or views
- All terminal interaction goes through `TerminalController` — never call `open -b` or `osascript` directly
- The CLI, hooks, and database are app-agnostic — no changes needed there
- Apps that reuse another terminal's env vars (like cmux setting `TERM_PROGRAM=ghostty` because it embeds libghostty) need an explicit higher-priority check in `TerminalApp.from(environment:)` so detection doesn't misroute to the shadowed app

### Security note

All strings interpolated into AppleScript (TTY paths, directory names) must go through `TerminalController.escapeForAppleScript()` to prevent injection. This escapes backslashes, quotes, and strips control characters. Any new AppleScript generation must use this function.

## Colors

UI colors live in `Sources/SeshctlUI/Theme.swift` — a single semantic-token namespace backed by `NSColor(name:dynamicProvider:)` so tokens flip on appearance change. Read the file header for the full pattern.

**Invariant:** never apply `.opacity(...)` to a `Theme.*` token at a call site. Bake the alpha into the token's provider (dark + light values each). Applying `.opacity(0.7)` to `Color.secondary` was the pattern that broke light mode — we explicitly reject it here.

**Adding a new token:** define the dark and light values, pick a semantic name, and wrap with `Theme.makeDynamic(name:) { appearance in ... }`. Use `appearance.isDarkMode` to branch. If the token needs to be used as a CGColor on a CALayer, expose it as both an `NSColor` and a SwiftUI `Color` — see `Theme.hudBorderNSColor` / `Theme.hudBorder`.

Adaptive single-color extensions (like `Color.assistantPurple`) follow the same pattern — see `RoleColors.swift`.

Per-repo accent colors are picked from `repoAccentPalette` in `RepoAccentColor.swift` (10 adaptive slots, each with a dark + light hex in the same hue family).

## Compatibility

See the compatibility tables in the [README](README.md#compatibility) for current LLM tool and terminal app support status. Keep those tables up to date when adding or changing support for a tool or terminal app.
