# Seshboard

## Build & Test

- **SwiftPM lock contention:** SwiftPM acquires a file lock on `.build/`. If a second `swift build` or `swift test` runs concurrently, it blocks indefinitely. Always use a **timeout of 120s** for builds and **30s** for test runs. If a build/test hangs or times out, immediately run `make kill-build` before retrying.
- `make kill-build` — force-kills all stale SwiftPM processes
- `make install` — build release + install CLI + hooks + restart app (full deploy)
- `make install-cli` — build release + install CLI to ~/.local/bin
- `make install-app` — build release + restart SeshboardApp
- `make install-hooks` — register Claude Code and Codex hooks in ~/.claude/settings.json and ~/.agents/hooks.json
  - **Codex hooks require a feature flag:** `codex_hooks = true` must be set in `~/.agents/config.toml`. The install script enables this automatically.
- `make uninstall` — stop app + remove CLI + unregister hooks
- `make uninstall-cli` — remove CLI from ~/.local/bin
- `make uninstall-app` — stop SeshboardApp
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
