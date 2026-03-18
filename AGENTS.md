# Seshboard

## Build & Test

- **SwiftPM lock contention:** SwiftPM acquires a file lock on `.build/`. If a second `swift build` or `swift test` runs concurrently, it blocks indefinitely. Always use a **timeout of 120s** for builds and **30s** for test runs. If a build/test hangs or times out, immediately run `make kill-build` before retrying.
- `make kill-build` — force-kills all stale SwiftPM processes
- `make install` — build release + install CLI + hooks + restart app (full deploy)
- `make install-cli` — build release + install CLI to ~/.local/bin
- `make install-app` — build release + restart SeshboardApp
- `make install-hooks` — register Claude Code and Codex hooks in ~/.claude/settings.json and ~/.agents/hooks.json
  - **Codex hooks require a feature flag:** `codex_hooks = true` must be set in `~/.agents/config.toml`. The install script enables this automatically.
- `make test` — run all tests
