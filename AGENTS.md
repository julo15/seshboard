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

Seshctl supports multiple terminal apps. Each app needs two things: **detection** (which app owns a session) and **focusing** (switching to the right tab/window when the user selects a session). The architecture has three integration patterns depending on the app's capabilities.

### How detection works

When `seshctl-cli start` runs, `detectHostApp()` in `Sources/seshctl-cli/SeshctlCLI.swift` walks the process tree from the shell PID upward, looking for a GUI app via `NSRunningApplication`. The bundle ID and name are stored in the database alongside the session. No per-app code is needed here — any app that launches a shell process is detected automatically.

If PID-based detection fails at focus time, `Sources/SeshctlUI/HostAppResolver.swift` falls back to checking `knownTerminals` — a hardcoded list of bundle IDs for apps that are likely to be the host.

### How focusing works

`Sources/SeshctlUI/WindowFocuser.swift` is the primary extensibility point. When the user presses Enter on a session, `focus(pid:directory:)` routes to the right strategy based on the host app's bundle ID.

**Pattern 1: TTY-matching AppleScript** (Terminal.app, iTerm2)

Used when the app exposes its tabs/sessions via AppleScript and each one has a TTY. The flow:
1. `open -b <bundleId>` brings the app to the foreground (handles cross-Space switching)
2. App-specific AppleScript iterates windows/tabs, matches by TTY path
3. Selects the matching tab

To add a new TTY-based app: add its bundle ID to `knownTerminals`, then add a case in `buildFocusScript()` with AppleScript that finds and selects the tab by TTY. Look at the iTerm2 case for the pattern — it searches `tty of s` across sessions within tabs within windows.

**Pattern 2: URI handler** (VS Code)

Used when the app doesn't expose terminals via AppleScript but supports a URI handler or extension API. The flow:
1. `open -b <bundleId> <directory>` brings the app forward
2. A URI like `vscode://julo15.seshctl/focus-terminal?pid=<pid>` triggers the companion extension
3. The extension (in `vscode-extension/`) finds the terminal by PID and focuses it

To add a new URI-based app: add a branch in `focus()` before the generic fallback, construct the appropriate URI, and build a companion extension for the target app.

**Pattern 3: Generic AppleScript fallback** (unknown apps)

For apps without specific support, a System Events script searches window names for the session's directory name and raises the matching window. This is less reliable but works as a baseline.

### What to touch for a new app

1. **`WindowFocuser.swift`** — add bundle ID to `knownTerminals`, add focus logic (AppleScript case or custom routing)
2. **`HostAppResolver.swift`** — add bundle ID to the fallback list if the app should be auto-detected
3. **`WindowFocuserTests.swift`** — add tests for app discovery, script generation, and focus routing
4. **Companion extension** (only if using the URI handler pattern)

The CLI, hooks, and database are app-agnostic — no changes needed there.

### Security note

All strings interpolated into AppleScript (TTY paths, directory names) must go through `escapeForAppleScript()` to prevent injection. This escapes backslashes, quotes, and strips control characters. Any new AppleScript generation must use this function.

## Compatibility

See the compatibility tables in the [README](README.md#compatibility) for current LLM tool and terminal app support status. Keep those tables up to date when adding or changing support for a tool or terminal app.
