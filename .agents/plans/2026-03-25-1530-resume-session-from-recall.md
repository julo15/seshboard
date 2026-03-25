# Plan: Resume Session from Recall Result

## Working Protocol
- Use parallel subagents for independent tasks (reading, searching, implementing across files)
- Mark steps done as you complete them
- Run `swift test --filter SeshctlCoreTests` and `swift build` after each step
- The VS Code extension changes are independent and can be done in parallel with Swift changes

## Overview
When a user presses Enter on a semantic search result that doesn't have an active session, seshctl should automatically open the right terminal app and resume the session — instead of just copying the resume command to clipboard. This requires two additions: (1) capturing launch args at session start so we can reconstruct the full command, and (2) per-app logic to open a terminal and execute the resume command.

## User Experience

1. User presses `/` and types a search query
2. Semantic results appear — some with green dots (active sessions), some with magnifying glass icons (inactive/unknown)
3. User presses Enter on an **active session** result → focuses the terminal (existing behavior, unchanged)
4. User presses Enter on an **inactive session** result (in DB but not running):
   - Seshctl checks if the project directory exists
   - Determines the target app (stored `hostAppBundleId` from the session)
   - Builds the resume command: `<tool> <stored_launch_args> --resume <conversation_id>`
   - Opens the app and executes the resume command in a new terminal tab
   - Dismisses the panel
5. User presses Enter on a **recall-only result** (not in DB):
   - Seshctl checks if the project directory exists
   - Determines the target app (frontmost known terminal app, since we don't have a stored host app)
   - Uses the recall result's `resume_cmd` as-is (we don't have stored launch args)
   - Opens the app and executes the resume command in a new terminal tab
   - Dismisses the panel
6. If the project directory doesn't exist → copies resume command to clipboard, shows brief feedback
7. If no known terminal app is running → copies resume command to clipboard (fallback)

## Architecture

### Current: Focus flow
1. User presses Enter → `handleRecallResult()` in AppDelegate
2. If matching session: `focusSession()` → `WindowFocuser.focus(pid:directory:)` → per-app AppleScript finds existing tab by TTY → selects it
3. If no matching session: `copyResumeCommand()` → clipboard

### New: Resume flow
1. User presses Enter → `handleRecallResult()` in AppDelegate
2. If matching **active** session: `focusSession()` (unchanged)
3. If matching **inactive** session (completed/stale/canceled):
   - Build resume command from: `session.tool` binary name + `session.launchArgs` + `--resume` + `session.conversationId`
   - Call `SessionResumer.resume(command:directory:bundleId:)`
4. If **recall-only** result (no DB session):
   - Use `result.resumeCmd` as the command
   - Detect frontmost terminal app via `NSWorkspace`
   - Call `SessionResumer.resume(command:directory:bundleId:)`
5. `SessionResumer` routes by bundle ID (same pattern as WindowFocuser):
   - **Terminal.app**: `open -b` then AppleScript `do script "<cmd>" in front window`
   - **iTerm2**: `open -b` then AppleScript `tell current session of current tab of current window` → `write text "<cmd>"`
   - **VS Code**: `open -b <bundleId> <directory>` then URI `vscode://julo15.seshctl/run-in-terminal?cmd=<encoded_cmd>`
   - **Fallback**: copy to clipboard
6. All strings interpolated into AppleScript go through `escapeForAppleScript()` (existing function in WindowFocuser)

### Launch args capture (at session start)
1. `SessionStart` hook fires → calls `seshctl-cli start --pid <PID> ...`
2. CLI's `Start.run()` calls `ps -p <pid> -o args=` to get the full command line
3. Strips the binary name (first component), stores the rest as `launch_args`
4. Saved to DB in new `launch_args TEXT` column

### Resume command reconstruction
- For sessions in DB: `<tool_binary> <launch_args> --resume <conversation_id>`
  - Tool binary: `claude` for .claude, `gemini` for .gemini, `codex` for .codex
  - launch_args: stored from session start (e.g., `--dangerously-skip-permissions`)
  - conversation_id: stored in session
- For recall-only results: use `result.resumeCmd` verbatim (already includes `cd` and `--resume`)

## Current State

### Key files
- `Sources/SeshctlUI/WindowFocuser.swift` — per-app focus logic, AppleScript generation, `escapeForAppleScript()`
- `Sources/SeshctlApp/AppDelegate.swift` — `handleRecallResult()` dispatches Enter on recall results
- `Sources/SeshctlCore/Database.swift` — migrations v1-v6, `startSession()`, `updateSession()`
- `Sources/SeshctlCore/Session.swift` — Session model with `hostAppBundleId`, `conversationId`, `tool`
- `Sources/seshctl-cli/SeshctlCLI.swift` — `Start` command captures PID, host app, git context
- `hooks/claude/session-start.sh` — passes `$PPID` to `seshctl-cli start`
- `vscode-extension/src/extension.ts` — URI handler for `focus-terminal` action

### Patterns to reuse
- `WindowFocuser.buildFocusScript()` — per-app AppleScript routing by bundle ID
- `WindowFocuser.escapeForAppleScript()` — string sanitization for AppleScript injection prevention
- `WindowFocuser.knownTerminals` — list of known terminal bundle IDs
- `WindowFocuser.SystemEnvironment` — protocol for testability (runAppleScript, runShellCommand)
- Database migration pattern — `migrator.registerMigration("vN")`

## Proposed Changes

### Component 1: Launch args capture
Add a `launch_args TEXT` column to the sessions table (migration v7). In `SeshctlCLI.Start.run()`, capture the tool process's command line via `ps -p <pid> -o args=`, strip the binary name, and pass it to `db.startSession()`. No hook changes needed — the CLI already has the PID.

### Component 2: SessionResumer (new)
A new struct in SeshctlUI (alongside WindowFocuser) that handles opening a terminal app and executing a command. Routes by bundle ID with per-app AppleScript, reusing `escapeForAppleScript()` and the `SystemEnvironment` protocol from WindowFocuser. Falls back to clipboard copy.

### Component 3: AppDelegate integration
Update `handleRecallResult()` to use SessionResumer instead of just copying to clipboard. For inactive DB sessions, reconstruct the resume command from stored data. For recall-only results, use the recall result's `resume_cmd`.

### Component 4: VS Code extension update
Add a new URI action `run-in-terminal` that creates a new terminal in the current window and runs a command. The URI format: `vscode://julo15.seshctl/run-in-terminal?cmd=<encoded_cmd>&cwd=<encoded_dir>`.

### Component 5: Frontmost terminal detection
Add a static method to detect the frontmost known terminal app via `NSWorkspace.shared.runningApplications`. Used when a recall result has no matching session in the DB.

### Complexity Assessment
**Medium-high.** 6-8 files changed/created across Swift and TypeScript. The per-app AppleScript is the trickiest part — Terminal.app and iTerm2 have different scripting models for executing commands vs. finding tabs. The VS Code extension change is small but requires TypeScript. The DB migration and CLI changes are straightforward. Risk is moderate — AppleScript behavior varies across macOS versions and app versions.

## Impact Analysis
- **New Files**:
  - `Sources/SeshctlUI/SessionResumer.swift` — per-app resume logic
  - `Tests/SeshctlUITests/SessionResumerTests.swift` — tests for command building, app routing
- **Modified Files**:
  - `Sources/SeshctlCore/Database.swift` — migration v7 (launch_args column)
  - `Sources/SeshctlCore/Session.swift` — add `launchArgs` field
  - `Sources/seshctl-cli/SeshctlCLI.swift` — capture launch args in Start command
  - `Sources/SeshctlApp/AppDelegate.swift` — update handleRecallResult to use SessionResumer
  - `vscode-extension/src/extension.ts` — add run-in-terminal URI handler
- **Dependencies**: Relies on WindowFocuser's SystemEnvironment protocol and escapeForAppleScript()
- **Similar Modules**: WindowFocuser (focus by PID) — SessionResumer is the complement (resume by command)

## Key Decisions
- **Launch args stored raw, not parsed** — LLM-agnostic, no per-tool flag knowledge needed
- **CLI captures args, not hooks** — single implementation point, CLI already has PID
- **Frontmost terminal for unknown sessions** — natural UX, user is probably in the app they want
- **Recall result's `resume_cmd` used as-is for non-DB results** — we don't have launch args to reconstruct

## Implementation Steps

### Step 1: DB migration and model update
- [x] Add migration v7 to `Sources/SeshctlCore/Database.swift`: `ALTER TABLE sessions ADD COLUMN launch_args TEXT`
- [x] Add `launchArgs` field to `Sources/SeshctlCore/Session.swift` with CodingKey `launch_args`
- [x] Update `startSession()` in Database.swift to accept `launchArgs` parameter

### Step 2: Capture launch args in CLI
- [x] In `Sources/seshctl-cli/SeshctlCLI.swift` `Start.run()`: after getting `pid`, run `ps -p <pid> -o args=`
- [x] Strip the binary name (first path component) from the output
- [x] Pass the remaining args string to `db.startSession(launchArgs:)`
- [x] Add `--launch-args` option to Start command as an override (optional, for testing)

### Step 3: SessionResumer — core logic
- [x] Create `Sources/SeshctlUI/SessionResumer.swift`
- [x] Add `static func resume(command: String, directory: String, bundleId: String?, environment: SystemEnvironment)` — routes by bundle ID
- [x] Add `static func buildResumeCommand(session: Session) -> String?` — reconstructs command from tool + launchArgs + conversationId
- [x] Add `static func detectFrontmostTerminal() -> String?` — returns bundle ID of frontmost known terminal app via NSWorkspace
- [x] Reuse `escapeForAppleScript()` from WindowFocuser (may need to make it internal/public if currently private)

### Step 4: Per-app AppleScript for resume
- [x] Terminal.app: `tell application "Terminal"` → `do script "<cmd>" in front window` (or `activate` + `do script` if no window)
- [x] iTerm2: `tell application "iTerm"` → `tell current session of current tab of current window` → `write text "<cmd>"` (or create new window if none)
- [x] Generic fallback: copy to clipboard
- [x] All commands go through `escapeForAppleScript()` for injection prevention

### Step 5: VS Code extension — run-in-terminal
- [x] In `vscode-extension/src/extension.ts`: add handler for `/run-in-terminal` path
- [x] Parse `cmd` and `cwd` query parameters (URL-decoded)
- [x] Create a new terminal via `vscode.window.createTerminal({ cwd })`
- [x] Send the command via `terminal.sendText(cmd)`
- [x] Focus the terminal via `terminal.show()`

### Step 6: AppDelegate integration
- [x] Update `handleRecallResult()` in AppDelegate to:
  - Check if matching session exists and is **inactive** → use SessionResumer with reconstructed command
  - Check if project directory exists (`FileManager.default.fileExists`)
  - For recall-only results → use SessionResumer with `result.resumeCmd` and detected frontmost terminal
  - Fallback to clipboard copy if directory missing or no terminal detected
- [x] Call `dismissPanel()` after initiating resume

### Step 7: Write tests
- [x] Create `Tests/SeshctlUITests/SessionResumerTests.swift`
  - [x] Test `buildResumeCommand` with various tools and launch args combinations
  - [x] Test `buildResumeCommand` returns nil when conversationId is missing
  - [x] Test `buildResumeCommand` handles empty launch args
  - [x] Test AppleScript generation for Terminal.app (escaping, command injection prevention)
  - [x] Test AppleScript generation for iTerm2
  - [x] Test routing by bundle ID (Terminal → Terminal script, iTerm → iTerm script, VS Code → URI, unknown → nil)
  - [x] Test `detectFrontmostTerminal` returns nil when no terminals running (mock NSWorkspace)
- [x] Update `Tests/SeshctlCoreTests/DatabaseTests.swift`
  - [x] Test that migration v7 adds launch_args column
  - [x] Test startSession with launchArgs parameter
  - [x] Test that existing sessions have nil launchArgs after migration

## Acceptance Criteria
- [x] [test] `buildResumeCommand` correctly reconstructs command from tool + launchArgs + conversationId
- [x] [test] AppleScript generation escapes all user-controlled strings
- [x] [test] Routing dispatches to correct app by bundle ID
- [x] [test] launch_args column is populated on new sessions
- [x] [test-manual] Enter on inactive session in Terminal.app opens new tab and resumes
- [x] [test-manual] Enter on inactive session in iTerm2 opens new session and resumes
- [x] [test-manual] Enter on inactive session in VS Code creates terminal and resumes
- [x] [test-manual] Enter on recall-only result uses frontmost terminal
- [x] [test-manual] Enter when project directory doesn't exist copies to clipboard
- [x] [test-manual] Launch args (e.g. --dangerously-skip-permissions) are preserved in resume command

## Edge Cases
- **Project directory deleted**: Check `FileManager.default.fileExists(atPath: directory)` before attempting resume. Fall back to clipboard copy.
- **No terminal app running**: `detectFrontmostTerminal()` returns nil → clipboard fallback.
- **Session has no conversationId**: `buildResumeCommand` returns nil → use recall result's `resume_cmd` if available, else clipboard.
- **Launch args contain quotes or special chars**: Stored raw, passed through `escapeForAppleScript()` when embedded in AppleScript.
- **VS Code not running but was the host app**: `open -b com.microsoft.VSCode <dir>` launches it, then URI handler fires after activation. May need a small delay.
- **Multiple windows in Terminal.app**: `do script` in `front window` targets the active window. User should see the command in the window they're looking at.
- **Tool binary not on PATH**: The resume command will fail in the terminal with "command not found". This is the same behavior as pasting the command manually — not something seshctl should handle.
