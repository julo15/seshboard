# Seshctl

## Build & Test

- **SwiftPM lock contention:** SwiftPM acquires a file lock on `.build/`. If a second `swift build` or `swift test` runs concurrently, it blocks indefinitely. Always use a **timeout of 120s** for builds and **30s** for test runs. If a build/test hangs or times out, immediately run `make kill-build` before retrying.
- `make kill-build` — force-kills all stale SwiftPM processes
- `make reinstall` — canonical dev loop: build + sign + install `Seshctl.app` to `/Applications` and re-launch. AppDelegate's launch-time reconciler refreshes the CLI symlink, standalone uninstaller, and hook registrations automatically.
- `make uninstall` — one-liner: runs `seshctl uninstall` against the installed CLI (CLI symlink + hook entries + standalone uninstaller + marker + `codex_hooks` flag). Drag `Seshctl.app` to Trash separately.
- `make cert-setup` — one-time: generate the self-signed code-signing identity in the login keychain.
- `make test` — run all tests

## Distributable App Build (Phase 1)

Seshctl ships as a self-signed `.app` bundle in a DMG. There is exactly one install surface — the bundled app — and two ways to produce it:

- **Dev iteration:** `make reinstall` → build + sign + drop `Seshctl.app` into `/Applications` + re-launch. Fast rebuild loop.
- **Release artifact:** `make dist` (= `bundle → sign → make-dmg`) → `dist/Seshctl-<VERSION>.dmg`. See [`docs/release.md`](docs/release.md) for the full release flow.

**Bundle metadata is in `Resources/Info.plist`** — that's the source of truth. `CFBundleShortVersionString` drives the DMG filename. Don't hard-code versions elsewhere.

**Code signing:** `Seshctl Self-Signed` in the user's login keychain. Set up via `make cert-setup` (one-time). The public cert PEM is committed at `Resources/seshctl-self-signed-public.pem`. See [`docs/signing.md`](docs/signing.md) for cert lifecycle, .p12 backup, and the future Developer ID upgrade.

**Install/uninstall logic** lives in `Sources/SeshctlCore/FirstLaunchInstaller.swift`. `AppDelegate` is the canonical install orchestrator: every `.app` launch reads the install marker, compares bundle path / version / executable mtime against the running bundle, and silently calls `FirstLaunchInstaller.install(bundleURL:)` on any mismatch — no welcome panel for upgrades, just refresh. End-user upgrades (drag a new DMG over the old one) and `make reinstall` both flow through this single path. Never duplicate the logic in bash again.

**Make targets:**
| Target | What |
|---|---|
| `make bundle` | Assemble `dist/Seshctl.app` from SwiftPM build (no signing) |
| `make sign` | Sign `dist/Seshctl.app` with the self-signed cert |
| `make make-dmg` | Create `dist/Seshctl-<VERSION>.dmg` |
| `make dist` | Full pipeline: `bundle → sign → make-dmg` |
| `make reinstall` | `bundle → sign`, then replace `/Applications/Seshctl.app` and re-launch (canonical dev loop) |
| `make cert-setup` | One-time: generate the self-signed cert in login keychain |
| `make uninstall` | One-liner: invokes `seshctl uninstall` (CLI symlink + hooks + standalone uninstaller + marker + `codex_hooks` flag) |

**Phase 2 will add Sparkle auto-updates.** Don't re-introduce manual update infrastructure as a "missing feature" — the plan deliberately defers it. See `.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md` and the README's "Roadmap" section.

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

**cmux fork — CLI dispatch via Unix socket** (separate from the AppleScript focus path above)

`SessionAction.forkSession` for cmux sessions routes through `TerminalController.forkCmuxAdjacent`, which drives cmux's bundled CLI (`<cmux.app>/Contents/Resources/bin/cmux`) over the Unix socket at `~/Library/Application Support/cmux/cmux.sock`. The dispatch chain is `tree --json --workspace <ws>` (find the source surface's pane id) → `new-surface --pane <pane>` → `tree --json` again (diff before/after to recover the new surface UUID) → `send --workspace <ws> --surface <new> -- <payload>`. Subprocess waits run on `DispatchQueue.global()` via `TerminalController.forkExecutor` with a 3-second per-call timeout so a wedged daemon never blocks the @MainActor panel.

**cmux socket auth — required user-side opt-in for fork to work.** cmux defaults `automation.socketControlMode` to `cmuxOnly`, which gates the socket on process ancestry: only descendants of the cmux GUI process are honored. SeshctlApp launched from the Dock, `make reinstall`, or a LaunchAgent has `launchd` (PID 1) as its ancestor — never cmux — so every CLI invocation returns `Failed to write to socket (Broken pipe, errno 32)` and `forkCmuxAdjacent` falls through to the `resume()` new-workspace path. To enable in-pane fork the user must set `automation.socketControlMode` to `"automation"` (socket stays `0600`, ancestry check disabled — the recommended mode) or `"allowAll"` (socket becomes `0666`, anyone in the user session can connect — looser, only choose with the trade-off in mind) in `~/.config/cmux/cmux.json` and restart cmux. The README `cmux setup` section is the user-facing copy; mirror any changes between the two. There is no daemon-side code-signature check or per-bundle-id allowlist — auth is purely (process ancestry → cmuxOnly) OR (password → password mode) OR (nothing → allowAll/automation), so no entitlement or signing trick on the SeshctlApp side can bypass `cmuxOnly`.

**Pattern 2: URI handler** (VS Code, VS Code Insiders, Cursor) — `supportsURIHandler` capability

`open -b` brings the app forward, then a URI handler (e.g. `vscode://julo15.seshctl/focus-terminal?pid=<pid>`) triggers the companion extension.

**Pattern 3: Generic AppleScript fallback** (unknown apps)

System Events script searches window names for the session's directory name and raises the matching window.

### How to add a new terminal app

1. **Add a case to the `TerminalApp` enum** in `TerminalApp.swift` — the compiler will show you every place that needs a handler (bundle ID, display name, URI scheme, capabilities)
2. **Add focus/resume AppleScript** in `TerminalController.buildFocusScript()` and/or `buildResumeScript()` if the app uses AppleScript
3. **(Optional) Add a same-pane fork dispatch** in `TerminalController.fork(...)` if the app exposes a CLI or AppleScript verb for opening a sibling surface in the existing pane (analogous to cmux's `forkCmuxAdjacent`). Without this, fork falls through to the new-window/new-tab `resume(...)` path, which is fine but loses the same-pane affordance.
4. **Add tests** in `Tests/SeshctlUITests/TerminalControllerTests.swift` for script generation and focus routing — and `ForkRoutingTests` for any fork-dispatch addition
5. **Build a companion extension** (only if using the URI handler pattern)

**Rules:**
- All bundle IDs and URI schemes live in `TerminalApp` — never hardcode them elsewhere
- All user actions go through `SessionAction.execute()` — never add focus/resume logic to AppDelegate or views
- All terminal interaction goes through `TerminalController` — never call `open -b` or `osascript` directly
- The CLI, hooks, and database are app-agnostic — no changes needed there
- Apps that reuse another terminal's env vars (like cmux setting `TERM_PROGRAM=ghostty` because it embeds libghostty) need an explicit higher-priority check in `TerminalApp.from(environment:)` so detection doesn't misroute to the shadowed app

### Security note

All strings interpolated into AppleScript (TTY paths, directory names) must go through `TerminalController.escapeForAppleScript()` to prevent injection. This escapes backslashes, quotes, and strips control characters. Any new AppleScript generation must use this function.

## Browser Tab Focusing

Browsers (Chrome / Arc / Safari) are NOT in `TerminalApp` — they don't host shell sessions. They live in a parallel registry/coordinator/controller stack:

- **`Sources/SeshctlCore/BrowserApp.swift`** — registry enum. Single source of truth for browser bundle IDs, display names, and AppleScript application names. Foundation-only (no AppKit). Every `switch` is exhaustive.
- **`Sources/SeshctlCore/ManagedTab.swift`** — `(browser, url)` value type. The `url` is the URL we last set on the tab; this is also the lookup key on the next flip. There is no per-browser tab id — Arc reissues numeric tab ids when a tab is promoted from Little Arc to a real sidebar window, Safari has no tab id at all, and unifying on URL keeps the three browsers' code paths uniform.
- **`Sources/SeshctlUI/BrowserController.swift`** — stateless namespace of AppleScript builders and pure helpers. `buildCombinedFocusScript`, `buildOpenTabScript`, `buildNavigateScript`, `defaultBrowser()`, `probeOrder(env:defaultBrowser:)`.
- **`Sources/SeshctlUI/RemoteBrowserCoordinator.swift`** — `final class` that owns the per-process managed-tab state. Public `openOrFocus(url:environment:)` runs the three-step decision:
  1. **Fast path: navigate-by-URL.** If we have a tracked managed tab, run `buildNavigateScript(browser:oldURL:newURL:)` against its browser. The script walks tabs and matches on the substring of the OLD URL we previously set; on hit it sets the new URL on the matched tab. On hit → update tracked URL. On miss → clear tracking and fall through.
  2. **Fallback: focus probe.** Build a single combined AppleScript across all running supported browsers (default-first). Each browser block walks tabs and matches on the substring of the new URL. On hit → focus, no tracking change.
  3. **Open new tab.** Run `buildOpenTabScript` in the user's default browser; it returns the sentinel `"<browser>:ok"` on success. Parse via `RemoteBrowserCoordinator.parseOpenTabOutput`, store `ManagedTab(browser, url)`. If the default isn't in our supported set or the open script fails, fall back to `env.openURL(url)` (NSWorkspace) with no tracking.

`AppDelegate` owns ONE coordinator instance and passes it to every `SessionAction.execute(...)` call. `SessionAction.openRemote` is the only call site — never call `BrowserController` or the coordinator from views.

**Identity is URL, not a per-browser tab handle.** This means a manually-opened tab at the same Claude session URL we tracked CAN be navigated by step 1 if the AppleScript walk happens to find it before our managed tab. This trade-off is documented and accepted: it keeps the code uniform across browsers and is robust to Arc's id-reassignment-on-promotion. Step 2 (focus probe) is non-mutating — it just brings the matched tab forward.

**Mock seam.** Tests use `MockSystemEnvironment` (in TerminalControllerTests) which captures executed scripts and returns canned stdout via `appleScriptOutputProvider`. The coordinator's 3-arg internal `openOrFocus(url:environment:defaultBrowser:)` lets tests inject a default browser without mutating any global.

**Arc multi-window — Accessibility required.** Arc's AppleScript dictionary refuses every "raise this window" verb (`set index`, `set frontmost`, `set main`, etc.) and rejects scalar property access (`bounds of w` errors -1728), so we can't bring the matched window forward from inside Arc's own tell block. Both `buildFocusBlock` and `buildNavigateScript` capture Arc's window UUID via `id of window N`, then call `System Events → tell process "Arc" → perform action "AXRaise"` on the AX window whose `AXIdentifier` contains that UUID (Arc surfaces it as `bigBrowserWindow-<UUID>`). AXRaise MUST run before `activate` — `activate` first causes Arc to paint its existing front window before AXRaise reorders the stack. AXRaise is wrapped in `try` so a missing Accessibility grant degrades gracefully to "matched tab is selected but wrong window stays front". `AppDelegate.applicationDidFinishLaunching` calls `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` so macOS prompts on first launch; the option key is hardcoded as a literal to sidestep Swift 6 strict-concurrency complaints about the C global being imported as `var`. Note: SeshctlApp is a bare SwiftPM binary (no .app bundle), so macOS may grant Accessibility by code-signature path without surfacing the app in the Settings list.

**To add a new browser:** add a case to `BrowserApp`, then handle the new case in `BrowserController.buildFocusBlock`, `buildOpenTabScript`, and `buildNavigateScript`. The compiler will surface every place that needs to be updated.

All AppleScript matchers must go through `TerminalController.escapeForAppleScript`.

## Compatibility

See the compatibility tables in the [README](README.md#compatibility) for current LLM tool and terminal app support status. Keep those tables up to date when adding or changing support for a tool or terminal app.
