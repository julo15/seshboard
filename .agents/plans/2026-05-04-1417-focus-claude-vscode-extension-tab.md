# Focus a specific tab of the Claude VS Code extension

**Status:** Not scheduled for implementation. Captured as a record after a research spike on 2026-05-04. Revisit if/when we want clicking a Claude-Code-in-VS-Code session to land the user in the Claude chat panel rather than the integrated terminal.

## Goal

When the user presses Enter (or invokes a `SessionAction`) on a row that represents a Claude Code session hosted **inside the official Claude VS Code extension** (`anthropic.claude-code`), focus the specific Claude chat tab for that session instead of treating the session as a generic VS Code terminal.

## Why this is feasible

The official extension at `~/.vscode/extensions/anthropic.claude-code-2.1.126-darwin-arm64/extension.js` registers a programmatic URI handler (not declared in `package.json`):

```
vscode://anthropic.claude-code/open?session=<uuid>&prompt=<text>
```

Internally `/open` calls `claude-vscode.primaryEditor.open(session, prompt)` → `Bf.createPanel(session, prompt, ViewColumn.Active)`. The branch we care about:

```js
if (sessionId) {
  let panel = this.sessionPanels.get(sessionId);
  if (panel) {
    panel.reveal();    // focuses the existing tab
    if (prompt) showInformationMessage("Session is already open. Your prompt was not applied.");
    return { startedInNewColumn: false };
  }
}
// else: creates a new editor panel; if the session UUID exists locally it resumes it
```

So the same URI does double duty: focus an open panel, or resume a closed session into a new panel. Same handler works on VS Code Insiders (`vscode-insiders://anthropic.claude-code/open?...`) and Cursor (`cursor://anthropic.claude-code/open?...`).

## Why this is mostly plumbing

The Claude session UUID is already captured end-to-end:

- `hooks/claude/session-start.sh:7` — extracts `session_id` from the SessionStart hook JSON payload and forwards it as `--conversation-id` to `seshctl-cli start`.
- `Sources/seshctl-cli/SeshctlCLI.swift:44,86` — `Start` command accepts and persists `--conversation-id`.
- `Sources/SeshctlCore/Session.swift:21` — `conversationId: String?` column, indexed in `Database.swift:56`.
- `Sources/SeshctlCore/TranscriptParser.swift:23` — already uses `conversationId` to find `~/.claude/projects/<encoded-dir>/<conversationId>.jsonl`.

No new capture layer is needed for the session UUID. Existing routing through `SessionAction.execute()` → `TerminalController` is the right entry point — see "How focusing and resuming works" in `AGENTS.md`.

## The core open question (the reason this isn't a one-PR change)

A Claude Code session hosted in the Claude extension's chat panel and a Claude Code session running in VS Code's integrated terminal **both fire the same start hook**, both produce a `conversationId`, and (today) both record `hostAppBundleId = "com.microsoft.VSCode"`. We do not currently distinguish them.

If we don't distinguish them, pressing Enter on either would have to pick one focus strategy and live with the wrong one half the time:

- Treating both as terminal sessions: extension-hosted sessions fail to focus (no terminal exists for them).
- Treating both as extension panels: terminal-hosted sessions get a stray new Claude panel opened on top of their actual terminal.

So step 1 of any real implementation is **adding a discriminator** to the captured session metadata.

### Detection signal

The Claude extension sets `CLAUDE_CODE_ENTRYPOINT="claude-vscode"` in the environment of the `claude` CLI it spawns (visible in the bundled `extension.js` near the `LV()` env-builder). The CLI in a regular shell does not set this. Other entrypoint values appear elsewhere in Anthropic's stack (e.g. `claude-code` for the bare CLI). This is the cleanest signal.

Open verification questions before relying on it:

1. **Does the SessionStart hook actually fire** when Claude is running as an extension panel? Hooks fire from the `claude` CLI; the extension does spawn the CLI binary (`resources/native-binaries/<platform>-<arch>/claude`) — confirmed by `Il4()` in `extension.js` — so they should. Verify by tailing the seshctl DB while opening a Claude panel in VS Code.
2. **Is `CLAUDE_CODE_ENTRYPOINT` actually present in the hook process environment**, or is it stripped before hooks run? The hook receives input as JSON on stdin; env vars are only available if the hook reads them directly (`process.env.CLAUDE_CODE_ENTRYPOINT` in the script).
3. **What value does `CLAUDE_CODE_ENTRYPOINT` take for VS Code Insiders and Cursor**? Probably the same `claude-vscode` string (the extension is identical across all three IDEs); we'd need to disambiguate the IDE separately, which we already do via `hostAppBundleId`.

## Implementation sketch

Assuming the verification questions above resolve favorably:

### 1. Capture the entrypoint

- `hooks/claude/session-start.sh` — read `$CLAUDE_CODE_ENTRYPOINT` from the hook process env, pass `--entrypoint "$CLAUDE_CODE_ENTRYPOINT"` (only when present).
- `Sources/seshctl-cli/SeshctlCLI.swift` — add `--entrypoint` option to `Start`; persist via `db.startSession(...)`.
- `Sources/SeshctlCore/Session.swift` — add `entrypoint: String?` column.
- `Sources/SeshctlCore/Database.swift` — schema migration adding the column (nullable, no default; existing rows stay null and are treated as "terminal" by default).
- Tests in `Tests/SeshctlCoreTests/DatabaseTests.swift` and `Tests/seshctl-cliTests/` covering the new field.

### 2. Add a capability and routing

- `Sources/SeshctlCore/TerminalApp.swift` — add `supportsClaudeExtensionFocus: Bool` capability. Set true for `.vsCode`, `.vsCodeInsiders`, `.cursor`. Adding it as a new capability rather than a new `TerminalApp` case is correct: the Claude extension is a feature of an IDE we already model, not a separate app. Every existing exhaustive switch will compile-fail until handled.
- `Sources/SeshctlUI/SessionAction.swift` — extend the routing chain so a session whose `entrypoint == "claude-vscode"` AND whose `hostAppBundleId` resolves to a `TerminalApp` with `supportsClaudeExtensionFocus == true` dispatches to a new `TerminalController` method instead of the existing terminal-focus path. Sessions with a null entrypoint keep current behavior.

### 3. Wire the URI in `TerminalController`

A new method `focusClaudeExtensionTab(in app: TerminalApp, conversationId: String, workspaceFolder: URL?) async`:

```
1. open -b <bundleId> [<workspaceFolder>]    // bring the right window forward
2. small delay (match existing 0.5s pattern in resumeInVSCode)
3. open "<scheme>://anthropic.claude-code/open?session=<uuid>"
   - scheme = vscode | vscode-insiders | cursor based on app
```

Two URI sends (immediate + delayed) like the existing `vscode://julo15.seshctl/...` calls — same race the existing code worked around.

No AppleScript needed. No companion-extension changes (this is a different extension and its URI handler is already there). No `escapeForAppleScript` involvement, but **do** percent-encode the UUID and any prompt parameter when building the URL.

### 4. Tests

- `Tests/SeshctlUITests/TerminalControllerTests.swift` — URI generation per IDE variant, percent-encoding of the session ID, branch selection by capability flag.
- `Tests/SeshctlUITests/SessionActionTests.swift` — routing: `entrypoint == "claude-vscode"` + VS Code host → extension-focus path; null entrypoint + VS Code host → terminal-focus path (existing).

### 5. Coverage check

Run `swift test --enable-code-coverage` and verify the modified files stay above 60% line coverage per `AGENTS.md`.

### 6. Compatibility table

Update README compatibility table: VS Code, VS Code Insiders, Cursor gain a "focus Claude extension panel" capability.

## Caveats and known limitations

These are properties of the Claude extension's URI handler, not bugs we'd introduce — but worth documenting in code comments next to the URI call so future readers understand the rough edges:

1. **Per-window only.** `sessionPanels` is held by one extension-host instance. With multiple VS Code windows open, only the foreground window handles the URI; that's why step 1 of the implementation opens the workspace folder first to surface the right window. If we don't know which workspace the session belongs to, we land in whichever VS Code window is frontmost. We *do* track workspace via the existing host-workspace-tracking work (see `2026-04-15-1200-vscode-host-workspace-tracking.md`), so this is solvable.
2. **Editor panel only.** The URI always routes through `primaryEditor.open`. A session currently shown in the **sidebar** would get duplicated as an editor tab. There's no documented URI for the sidebar webview, and the `claude-vscode.sidebar.open` command takes no arguments — so sidebar-resident sessions cannot be focused by UUID. Minor UX wart; acceptable.
3. **Prompt parameter is silently swallowed** if the panel is already open (a VS Code info toast says so). Not relevant for focus, would matter if we ever wanted to send a prompt from seshctl into an existing session.
4. **Workspace mismatch.** If we ask the extension to open a session UUID that isn't local to the current workspace, the extension creates a new empty panel under that ID rather than refusing. The seshctl row → workspace mapping should already be correct because we capture the `cwd` at hook time, but worth a unit test.
5. **VS Code routing.** macOS routes `vscode://` URIs to the most recently focused VS Code instance. The `open -b <bundleId> <workspaceFolder>` step is load-bearing; without it, the URI lands in whichever window happens to be frontmost.
6. **Sidebar entrypoint is indistinguishable.** `CLAUDE_CODE_ENTRYPOINT="claude-vscode"` is set whether the user opened the panel via the editor command, sidebar command, or new-window command — so we can't tell from hook-time data which surface the session lives on. We'd always try the editor-panel URI; a sidebar session would get duplicated (limitation #2 above).

## What's not in scope

- Resuming a Claude session that ended into a *terminal* (the existing `vscode://julo15.seshctl/run-in-terminal` path remains for terminal-hosted sessions).
- Any change to the Claude.app native desktop app integration (separate code path; see commit `9527de4`).
- Any change to remote/SSH or cmux Claude sessions (different host stacks).
- Sending prompts into an existing Claude panel (extension swallows the param).
- Focusing sidebar-resident Claude sessions (no documented mechanism).

## Estimated cost

Small-to-medium. Roughly:

- 1 schema column + migration + tests
- 1 hook line + CLI flag + tests
- 1 capability + 1 controller method + routing branch + tests
- README table touch

The only thing that could blow this up is if verification question #2 (env var visibility in the hook) goes the wrong way; in that case we'd need a different discriminator, e.g. process-tree introspection that distinguishes "claude spawned by VS Code extension host" from "claude spawned by VS Code integrated terminal shell." That's possible but uglier.

## References

- Installed extension: `~/.vscode/extensions/anthropic.claude-code-2.1.126-darwin-arm64/extension.js`
- URI-handler block: search `extension.js` for `registerUriHandler` (single occurrence).
- `createPanel` reuse logic: search `extension.js` for `sessionPanels.get` (the `panel.reveal()` branch).
- seshctl session capture: `hooks/claude/session-start.sh:7`, `Sources/seshctl-cli/SeshctlCLI.swift:44,86`, `Sources/SeshctlCore/Session.swift:21`.
- Existing VS Code focus pattern (terminal): `Sources/SeshctlUI/TerminalController.swift:719–748`, `vscode-extension/src/extension.ts`.
- Workspace tracking precedent: `.agents/plans/2026-04-15-1200-vscode-host-workspace-tracking.md`.
