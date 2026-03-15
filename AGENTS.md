# Seshboard

## Build & Test

- **Never run `swift build` or `swift test` in the background, via subagents, or in parallel.** SwiftPM acquires a file lock on `.build/` and any concurrent invocation will block indefinitely, causing timeouts and preventing the user from building in their terminal.
- Always run builds/tests in the foreground with a reasonable timeout.
- If a build hangs, kill stale SwiftPM processes: `make kill-build`
- Use `make install` to build+install CLI, `make restart` to rebuild+restart app
