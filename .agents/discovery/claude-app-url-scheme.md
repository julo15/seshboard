# Claude.app `claude://` URL Scheme

Reverse-engineered from `/Applications/Claude.app` v1.3561.0 (CFBundleVersion, built against macOS 15.5 SDK). The scheme is undocumented; everything here comes from reading the Electron shell's extracted `app.asar`. Re-verify when Claude.app ships a new major version.

> ⚠️ **Private, undocumented, subject to change**. Anthropic has not published this scheme. The symbol names, route mappings, and internal path layouts described below (`Ine`, `qbr`, `Bu`, `VD`, `/epitaxy/*`, etc.) are minifier output that may change on any release. Do not bake the internal symbol names into production code. Prefer the stable public URL surfaces (`claude://resume?session=<uuid>`, `claude://claude.ai/chat/<uuid>`) when seshctl acts on them, and treat the rest as diagnostic reference.

## TL;DR for seshctl routing

| Row type | Deep link | Status |
|---|---|---|
| Local Claude Code CLI session (captured via hooks) | `claude://resume?session=<CLI_SESSION_UUID>` | ✅ Works. Idempotent. First-class handler. |
| Remote Claude Code session (Code tab in Claude.app, `cse_<id>` from claude.ai API) | *(none)* | ❌ No working deep link exists. Fall back to `https://claude.ai/code/session_<suffix>` in browser. |
| Web chat conversation | `claude://claude.ai/chat/<UUID>` | ✅ Works for claude.ai chats (not applicable to seshctl's Code-session rows). |

## Registered protocol

From `Info.plist`:

```
CFBundleURLTypes → [ { CFBundleURLName: "Claude", CFBundleURLSchemes: ["claude"] } ]
```

The handler accepts five protocol aliases: `claude:`, `claude-dev:`, `claude-nest:`, `claude-nest-dev:`, `claude-nest-prod:`.

## Full route table

The `open-url` handler (minified name `Ine` in `.vite/build/index.js`) switches on `new URL(...).host`:

| Host | Path | Effect |
|---|---|---|
| `preview` | — | no-op outside nest builds |
| `hotkey` | — | no-op |
| `cowork` | `/new?q=…&folder=…&file=…` | prefill a new Cowork session |
| `code` | `/new?q=…&folder=…&file=…` | open Claude Code desktop, new session with prefilled prompt/folders |
| `resume` | `?session=<UUID>` | **import a Claude Code CLI session and navigate to it** |
| `login` | `/google-auth?code=…&anon_id=…` | Google SSO callback |
| `claude.ai` | `/<subroute>/…` | main claude.ai app routes (see below) |

### `claude://claude.ai/<subroute>` values (`Bu` enum)

| Subroute (URL value) | Enum name | Handling |
|---|---|---|
| `chat` | `OpenConversation` | validates UUID, navigates to `/chat/<UUID>` |
| `project` | `OpenProject` | validates UUID, navigates to `/project/<UUID>` |
| `new` | `New` | new conversation, optional `?q=` prefill |
| `magic-link` | `MagicLink` | login magic link |
| `sso-callback` | `SSOCallback` | SSO callback |
| `mcp-auth-callback` | `McpAuthCallback` | MCP OAuth callback |
| `settings` / `admin-settings` / `local_sessions` / `create` / `tasks` / `claude-code-desktop` / `customize` | (various) | pass-through `loadURL` to `https://claude.ai/<subroute>/<rest>` |
| *(any other)* | — | falls through to `dispatchHandleDeepLink(url)` IPC → renderer |

## Local CLI session resume (works)

```
claude://resume?session=<CLI_SESSION_UUID>
```

Example:

```
open "claude://resume?session=7f3b1234-5678-9abc-def0-1234567890ab"
```

The UUID must match the standard `/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/` regex, and is the bare filename UUID of `~/.claude/projects/**/<uuid>.jsonl`.

Flow:
1. Handler calls `LocalSessionManager.importCliSession(uuid)`.
2. `importCliSession` is **idempotent**: it caches the session internally as `local_<uuid>` (prefix constant `VD = "local_"`), returns the cached ID on repeat invocations, then calls `dispatchNavigate("/epitaxy/local_<uuid>")`.
3. Window is focused/restored by the `second-instance` / `open-url` handlers (`BrowserWindow.show() / restore() / focus()`).

Safe to invoke every time — no duplicate imports, no new windows. This is the pathway seshctl should use for local Claude Code rows.

## Remote Code-tab session focus (no working deep link)

Code-tab remote sessions in Claude.app correspond to the sessions returned by claude.ai's API as `cse_<id>`; the claude.ai web path uses `session_<id>` (same ID, different prefix). Seshctl's `RemoteClaudeCodeSession.webUrl` already produces the browser form:

```swift
// Sources/SeshctlCore/RemoteClaudeCodeSession.swift
public var webUrl: URL {
    let suffix = id.hasPrefix("cse_") ? String(id.dropFirst("cse_".count)) : id
    return URL(string: "https://claude.ai/code/session_\(suffix)")!
}
```

Empirically tested `claude://` variants and why each fails:

### `claude://claude.ai/code/session_<suffix>` → blank white window

1. `Ine` routes host=`claude.ai`, first path segment = `code`, which is **not** an explicit case in the `Bu` switch. Falls through to `default` → `LKA.getDispatcher(...).dispatchHandleDeepLink("https://claude.ai/code/session_<suffix>")` sends IPC to the main window renderer.
2. The renderer's web app apparently calls `window.open(...)` or an equivalent for `/code/...` URLs.
3. `setWindowOpenHandler` explicitly special-cases `/code/*` via predicate `FBA` (`pathname.split("/")[1] === Bu.Code`):

    ```js
    webContents.setWindowOpenHandler(({ url: E }) => {
      const u = new URL(E);
      const C = u.searchParams.get(fBt) !== null;  // fBt = "open_in_browser"
      if (FBA(u) && !C) {
        const B = qbr();  // find existing Claude Code window
        return B
          ? (B.show(), { action: "deny" })  // reuse: show, no navigate
          : {
              action: "allow",
              overrideBrowserWindowOptions: {
                ...Jbr(),  // title "Code", size 850x700
                webPreferences: {
                  preload: ".vite/build/mainView.js",
                  ...
                }
              }
            };
      }
      return KZ(E), { action: "deny" };  // open externally
    });
    ```

4. If no existing Code window → Electron spawns a fresh 850x700 BrowserWindow with `mainView.js` preload and `loadURL`s the URL directly.
5. The Code sub-window doesn't reuse the main window's `/epitaxy` hydration path — it raw-loads whatever URL came from `window.open()`, which doesn't render Code-tab content. Blank white.

**Notable**: this path *is* recognized — a random URL like `claude://claude.ai/foobar` falls to the same `default` IPC but the web app ignores it (no window opens). `/code/` is structurally special, just not in a way that's usable for session focus.

### `claude://claude.ai/local_sessions/<cse_id>` → "starting new session" fallback

1. `Bu` switch matches `Bu.LocalSessions`, calls `j1A(o, t, A)` which `loadURL`s `https://claude.ai/local_sessions/<cse_id>` in the main webContents.
2. `local_sessions` is the **Cowork** lane — a distinct session class from Code-tab remote sessions. Triggered by `getFocusedSessionRoute`:

    ```js
    getFocusedSessionRoute(A, t) {
      return A === "cowork" ? `/local_sessions/${t}` : Ko.getSessionRoute(t);
    }
    ```

3. Web router can't map `cse_<id>` to a cowork session → falls back to "start new session" UI.

### Why no mapping from `cse_<id>` to internal ID exists

Claude.app's internal session IDs are desktop-assigned, not API-derived:

- CLI import: `local_<cliUuid>` (via `importCliSession`, key constants `em = "local_"`, `VD = "local_"`, `IXe = "local_"`)
- Sessions-bridge `startChildSession`: `` `local_${randomUUID()}` `` — fresh random ID, no deterministic link to `cse_<id>`
- Dittos: `local_ditto_<id>` via `OgA(e, A)` — a specific worktree-spawned subset

No `importRemoteSession` / `openRemoteSession` / `cse_` lookup exists anywhere in the asar. The claude.ai web URL `/code/session_<id>` is rendered server-side by claude.ai — the Electron shell has no way to translate it to an `/epitaxy/<internalId>` route.

## Code tab vs. "Cowork" terminology

Confusing. What users see as the **Code tab** in Claude.app corresponds to:

- `sidebarMode` enum values: `"chat" | "code" | "task" | "epitaxy" | "operon"`
- Internal path: `code → epitaxy` (explicit map `u = E === "code" ? "epitaxy" : E` at window-load time)
- Session route: `/epitaxy/<internalId>`
- Predicate: `UUi(url) = pathname === "/epitaxy" || startsWith("/epitaxy/")`

**Cowork** is a separate session class (`getFocusedSessionRoute(A === "cowork")` → `/local_sessions/<id>`), not the Code tab. The `claude://cowork/new` URL and the `/local_sessions/` path are both Cowork-specific.

## Gotchas (from upstream bug reports)

- **macOS full-screen bug** ([anthropics/claude-code#22691](https://github.com/anthropics/claude-code/issues/22691)): `claude://` callbacks don't foreground the app when a browser is in macOS native full-screen mode. Workaround: exit full screen before invoking.
- **Third-party custom-scheme passthrough** ([#26952](https://github.com/anthropics/claude-code/issues/26952)): Electron shell blocks outgoing clicks on third-party custom URL schemes. Doesn't affect `claude://` itself.
- **Windows OAuth forwarding** ([#31476](https://github.com/anthropics/claude-code/issues/31476)): Windows Store installs spawn new processes instead of forwarding. Irrelevant on macOS.

## Applying to seshctl

In `Sources/SeshctlUI/SessionAction.swift` (the routing entry point for Enter on a row):

- **Local CLI session row** → build `claude://resume?session=<cliUuid>` using the CLI session UUID captured by seshctl's `SessionStart` hook. Invoke via `NSWorkspace.shared.open(url)`. Idempotent; no extra state needed.
- **Remote Code session row** → current `RemoteClaudeCodeSession.webUrl` (browser fallback) remains the best option. Alternative: focus Claude.app (`open -b com.anthropic.claudefordesktop`) without session-specific navigation and let the user pick the session in the Code tab.
- **Future option** → file feedback requesting a `claude://code/resume?session=<cse_id>` parity handler; once shipped, add a new `Bu.Resume`-style branch in `TerminalApp.swift` capabilities.

## How to re-verify on a new Claude.app version

```bash
# 1. Confirm scheme is still registered
plutil -p /Applications/Claude.app/Contents/Info.plist | grep -A3 CFBundleURLSchemes

# 2. Extract app.asar (requires Node ≥22.12; asdf 22.22.2 works, 22.2.0 does not)
ASDF_NODEJS_VERSION=22.22.2 npx @electron/asar extract \
  /Applications/Claude.app/Contents/Resources/app.asar \
  /tmp/claude-asar-extracted

# 3. Find the open-url handler
grep -n 'setAsDefaultProtocolClient("claude")' \
  /tmp/claude-asar-extracted/.vite/build/index.js
```

Key symbols to trace in `.vite/build/index.js`:

- `Ine(url, webContents)` — the top-level `claude://` handler (switch on `t.host`)
- `AL` enum — top-level hosts (`hotkey`, `login`, `claude.ai`, `preview`, `cowork`, `code`)
- `Bu` enum — `claude.ai/<subroute>` values
- `V1A` — UUID regex
- `j1A(e, A, t)` — pass-through `loadURL` for known-but-unhandled subroutes
- `rb(path, webContents)` — dispatches `navigate` IPC, falls back to `loadURL`
- `Ko.importCliSession(uuid)` — idempotent CLI import, returns `local_<uuid>`
- `Ko.getSessionRoute(id)` — returns `` `/epitaxy/${encodeURIComponent(id)}` ``
- `FBA(url)` — predicate: is this a `/code/*` URL that needs the Code sub-window?
- `qbr()` / `Jbr()` / `c1t()` — Code window accessor / bounds / creator
