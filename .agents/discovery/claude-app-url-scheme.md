# Claude.app `claude://` URL Scheme & Handoff

Reverse-engineered from `/Applications/Claude.app`. Last re-verified against **v1.5220.0** (CFBundleVersion) on 2026-04-29; previously verified against v1.3883.0 (2026-04-22) and v1.3561.0. The scheme is undocumented; everything here comes from reading the Electron shell's extracted `app.asar`. Re-verify when Claude.app ships a new major version.

> ⚠️ **Private, undocumented, subject to change**. Anthropic has not published this scheme. The symbol names, route mappings, and internal path layouts described below (`dEe`, `ZR`, `DE`, `hei`, `/epitaxy/*`, etc.) are minifier output that may change on any release. Do not bake the internal symbol names into production code. Prefer the stable public URL surfaces (`claude://resume?session=<uuid>`, `claude://claude.ai/chat/<uuid>`, `claude://code/new`) when seshctl acts on them, and treat the rest as diagnostic reference.

## TL;DR for seshctl routing

| Row type | Mechanism | Status |
|---|---|---|
| Local Claude Code CLI session (captured via hooks) | `claude://resume?session=<CLI_SESSION_UUID>` URL | ✅ Works. Idempotent. First-class handler. Unchanged across 1.3561 → 1.5220. |
| New Code-tab session with prefilled prompt / folders | `claude://code/new?q=…&folder=…&file=…` URL | ✅ Works. Added in 1.3883, unchanged in 1.5220. |
| Remote Code session (Code tab, `cse_<id>` from claude.ai API) | `claude://claude.ai/code/session_<suffix>` URL | ❌ Still broken in 1.5220. Falls through to `dispatchHandleDeepLink`; the spawned Code sub-window loads a blank page. |
| Remote Code session (`cse_<id>`) | **NSUserActivity / macOS Handoff**, activity type `com.anthropic.claude.code.session` (renamed in 1.5220) | ❌ Code path exists in v1.5220 (would navigate to `/epitaxy/<localId>` or `/code/<cse_id>`), but empirically did not deliver from a same-device peer process when tested against v1.3883. macOS Handoff is cross-device-only in practice. The handler structure is unchanged in 1.5220 — same conclusion expected. See "Remote Code-tab session focus via Handoff" below. |
| Web chat conversation | `claude://claude.ai/chat/<UUID>` URL | ✅ Works. |

## What changed between v1.3883.0 and v1.5220.0

1. **Handoff activity type renamed** (most user-visible change). `Info.plist` `NSUserActivityTypes` is now `["com.anthropic.claude.code.session"]` (was `"com.anthropic.claude.session"`). The handler constant changed too (`bUn = "com.anthropic.claude.code.session"`). Payload shape, version field (`v: 1`), validator regex, and feature flag (`2049450122`) are unchanged. Any external poster of the activity must use the new type string.
2. **Handoff payload validator now logs warnings on rejection.** `UUn` (was `GLr`) emits structured `R.warn("handoff: ignoring activity with …")` for unexpected version, missing required fields, or malformed `sessionId`. Useful for debugging — `~/Library/Logs/Claude/main.log` will show the rejection reason.
3. **`Resume` is now a proper outer-switch case.** In 1.3883 the `claude://resume?…` URL matched only because the subroute enum value `QE.Resume === "resume"` happened to collide with `t.host`. In 1.5220 the case is written as `case DE.Resume:` directly inside the outer `switch (t.host)` (the enum was renamed `QE → DE`). Behavior identical, structure cleaner.
4. **No new path for remote Code-session focus.** `claude://claude.ai/code/...` is still in `DE.Code` enum but still NOT handled by the inner `claude.ai` switch — falls through to `dispatchHandleDeepLink`, same blank Code sub-window. No new `code/resume`, `code/focus`, or remote-import URL surface.
5. **Minifier symbol shuffle** — handler `qne → dEe`, top-level enum `SR → ZR`, subroute enum `QE → DE`, dispatch helper `gb → vL`, pass-through loader `m2A → wKA`, local session manager `no → Ys`, UUID regex `f2A → pKA`, Code-window predicate `cQA → FpA`, Code window accessor `OLr → PUn`, Code-host whitelist `PLr → YUn`, Handoff dispatcher `GFt → hei`, payload validator `GLr → UUn`, feature-flag gate `bLr → LUn`, activity-type constant `kLr → bUn`, GrowthBook helper `Ii → xt`, telemetry helper `mt → It`. Tracked below under "Re-verify".

## What changed between v1.3561.0 and v1.3883.0

1. **NSUserActivity Handoff path added** (biggest change). `Info.plist` now declares `NSUserActivityTypes = ["com.anthropic.claude.session"]`, and the app listens for `continue-activity`. Payload is `{v:1, sessionId:<string>, organizationId:<string>}`. Matches `^[A-Za-z0-9_-]+$` so `cse_<id>` IDs are accepted. Navigation target: `/epitaxy/<localId>` if the session has been bridged into the desktop (`findSessionIdByBridgeSessionId`), else `/code/<sessionId>`. Feature-gated by `isFeatureEnabled("2049450122")`.
2. **`claude://code/new` route added** — parity with the existing `claude://cowork/new`. Accepts `q` (prompt, aliased `prompt`), `folder` (repeatable), `file` (repeatable). Dispatches `navigate` to `/epitaxy?q=…&folder=…&src=external`.
3. **`claude://debug-handoff` route added** — nest-builds only. `M.warn("debug-handoff is only available in nest builds")` in shipping app. Unusable.
4. **Enum reorganization** — `resume` moved from a standalone `AL`/`SR` top-level host into the `Bu`/`QE` claude.ai-subroute enum (`QE.Resume = "resume"`). The outer switch is still `switch(t.host)`, so `claude://resume?session=<uuid>` continues to match because `QE.Resume === "resume"`. Behavior identical. Similarly, `QE.Code = "code"` was added but is not wired into the inner claude.ai switch — only the new top-level `SR.Code` case (point 2) is active.
5. **Minifier symbol shuffle** — internal handler renamed `Ine → qne`, predicate `FBA → cQA`, Code window accessor `qbr → OLr`, etc. Tracking these below under "Re-verify".

## Registered protocol

From `Info.plist`:

```
CFBundleURLTypes → [ { CFBundleURLName: "Claude", CFBundleURLSchemes: ["claude"] } ]
NSUserActivityTypes → [ "com.anthropic.claude.code.session" ]   # renamed in 1.5220 (was "com.anthropic.claude.session" in 1.3883)
```

Protocol aliases (unchanged): `claude:`, `claude-dev:`, `claude-nest:`, `claude-nest-dev:`, `claude-nest-prod:`.

## Full route table (v1.5220.0)

The `open-url` handler (minified name `dEe` in `.vite/build/index.js`, was `qne` in 1.3883) switches on `new URL(...).host`. Enum `ZR` holds top-level hosts (was `SR`); enum `DE` holds claude.ai sub-routes (was `QE`). In 1.5220 the outer switch has explicit cases for `ZR.{Preview, Hotkey, DebugHandoff, Cowork, Code, Login, ClaudeAI}` plus `DE.Resume` (the only `DE.*` value handled at the outer level — see "What changed" point 3).

| Host | Path | Effect |
|---|---|---|
| `preview` | — | no-op outside nest builds |
| `hotkey` | — | no-op |
| `debug-handoff` | — | **nest-only**, logs warning and returns (new in 1.3883) |
| `cowork` | `/new?q=…&folder=…&file=…` | prefill a new Cowork session |
| `code` | `/new?q=…&folder=…&file=…` | opens Code tab, new session with prefilled prompt/folders. Navigates to `/epitaxy?q=…` (added 1.3883) |
| `resume` | `?session=<UUID>` | import a Claude Code CLI session and navigate to it (in 1.5220 handled by an explicit `case DE.Resume:` in the outer switch — same behavior, cleaner structure) |
| `login` | `/google-auth?code=…&anon_id=…` | Google SSO callback |
| `claude.ai` | `/<subroute>/…` | main claude.ai app routes (see below) |

### `claude://claude.ai/<subroute>` values (`DE` enum, was `QE` in 1.3883)

| Subroute (URL value) | Enum name | Handling |
|---|---|---|
| `chat` | `OpenConversation` | validates UUID, navigates to `/chat/<UUID>` |
| `project` | `OpenProject` | validates UUID, navigates to `/project/<UUID>` |
| `new` | `New` | new conversation, optional `?q=` prefill |
| `magic-link` | `MagicLink` | login magic link |
| `sso-callback` | `SSOCallback` | SSO callback |
| `mcp-auth-callback` | `McpAuthCallback` | MCP OAuth callback |
| `settings` / `admin-settings` / `local_sessions` / `create` / `tasks` / `claude-code-desktop` / `customize` | (various) | pass-through `loadURL` to `https://claude.ai/<subroute>/<rest>` |
| `code` / `resume` | `Code` / `Resume` | **Present in enum but NOT in inner switch.** Falls through to default (`dispatchHandleDeepLink`). Effectively a no-op for `claude://claude.ai/code/...` and `claude://claude.ai/resume/...`. |
| *(any other)* | — | falls through to `dispatchHandleDeepLink(url)` IPC → renderer |

## Local CLI session resume (works)

```
claude://resume?session=<CLI_SESSION_UUID>
```

Example:

```
open "claude://resume?session=7f3b1234-5678-9abc-def0-1234567890ab"
```

The UUID must match the standard `/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/i` regex (symbol `pKA` in 1.5220, was `f2A` in 1.3883), and is the bare filename UUID of `~/.claude/projects/**/<uuid>.jsonl`.

Flow (unchanged from 1.3561):

1. Handler calls `LocalSessionManager.importCliSession(uuid)` (symbol `Ys.importCliSession` in 1.5220, was `no.importCliSession` in 1.3883).
2. `importCliSession` is **idempotent**: it caches the session internally as `local_<uuid>`, returns the cached ID on repeat invocations, then calls `dispatchNavigate("/epitaxy/local_<uuid>")`.
3. Window is focused/restored by the `second-instance` / `open-url` handlers.

Safe to invoke every time — no duplicate imports, no new windows. This is the pathway seshctl uses for local Claude Code rows.

## New Code-tab prefill (works, added in 1.3883, unchanged in 1.5220)

```
claude://code/new?q=<prompt>&folder=<abs-path>&folder=<abs-path-2>&file=<abs-path>
```

Handler (`index.pretty.js:398648` in v1.5220):

```js
case ZR.Code: {
  if (t.pathname !== "/new") { R.warn(...); return }
  const s = t.searchParams.get("q") ?? t.searchParams.get("prompt"),
        o = s?.slice(0, sjA),  // prompt, length-capped
        a = t.searchParams.getAll("folder"),
        c = t.searchParams.getAll("file"),
        g = new URLSearchParams;
  o && g.set("q", o);
  for (const I of a) g.append("folder", I);
  a.length > 0 && g.set("src", "external");
  const u = g.toString() ? `/epitaxy?${g}` : "/epitaxy";
  It("desktop_code_deeplink_received", { has_prompt: !!o, has_folder: a.length > 0, has_file: c.length > 0 });
  vL(u, A);  // dispatchNavigate
  return
}
```

Notes:
- `file=` is accepted and telemetered but **not re-emitted** in the destination URL — only `folder` entries are forwarded.
- `prompt` is an alias for `q`.
- Prompt length is clamped by `sjA` (was `OqA` in 1.3883; numeric value not inspected).
- No way to target a specific existing Code session via this route — it's new-session-only.

## Remote Code-tab session focus via Handoff (added in 1.3883, activity type renamed in 1.5220, still does not work for our use case)

> **Empirical result (2026-04-22, against v1.3883):** Posting an `NSUserActivity` of type `com.anthropic.claude.session` from a same-machine peer process (standalone Swift script, then activating Claude.app via `NSWorkspace.openApplication`) **did not fire** Claude.app's `continue-activity` handler. Claude.app's `~/Library/Logs/Claude/main.log` showed zero handoff log entries after the test, and `GFt` (now `hei`) logs unconditionally on entry — so the OS never delivered the activity. macOS Handoff is a cross-device feature (iCloud-synced via Bluetooth/WiFi to the same Apple ID's other devices, with a user-click on a Handoff indicator); same-Mac cross-process delivery is not a documented capability. **Do not rely on this path from seshctl.**
>
> **v1.5220 status (2026-04-29):** The activity type has been renamed to `com.anthropic.claude.code.session`, but the handler structure is otherwise identical. Not re-tested empirically against 1.5220 — the conclusion is expected to hold because the limitation is in macOS, not in Claude.app's code. If you do re-test, **use the new activity type string**.
>
> The mechanism is documented below for completeness — it would work as described if Claude.app received the activity, e.g. from the iOS Claude app or another signed-in Mac doing a real Handoff. The seshctl prototype that wrapped this path was reverted (`ClaudeAppHandoff.swift`, `SessionActionTarget.openRemoteClaudeCode`) — see git history if you need to resurrect it for the cross-device case.

This is — on paper — the only working path to focus a specific `cse_<id>` remote Code session in Claude.app. It uses macOS Handoff's `NSUserActivity` + `continue-activity` hook, **not** a URL scheme.

Handler (`index.pretty.js:398548` in v1.5220):

```js
const bUn = "com.anthropic.claude.code.session";  // activity type (renamed in 1.5220)
const GUn = 1;                                    // payload version

function LUn() { return xt("2049450122"); }       // GrowthBook feature flag

function UUn(e) {                                 // payload validator
  if (!e) return null;
  const A = e.v;
  if (A !== GUn) { R.warn("handoff: ignoring activity with unexpected version", { version: A }); return null; }
  const t = e.sessionId, i = e.organizationId;
  if (typeof t !== "string" || typeof i !== "string") {
    R.warn("handoff: ignoring activity with missing required fields"); return null;
  }
  if (!/^[A-Za-z0-9_-]+$/.test(t)) {
    R.warn("handoff: ignoring activity with malformed sessionId"); return null;
  }
  return { sessionId: t, organizationId: i };
}

function hei(e, A) {                              // main dispatcher (was GFt)
  if (!LUn()) { R.info("handoff: feature disabled, ignoring continuation"); return; }
  const t = UUn(e);
  if (!t) return;
  const i = DB.getDispatcher(A.webContents);
  if (!i) return;
  const r = Ys.findSessionIdByBridgeSessionId(t.sessionId),
        n = r ? Ys.getSessionRoute(r) : `/code/${t.sessionId}`;
  i.dispatchNavigate(n);
}

// Wiring still uses fA.app.on("continue-activity", ...) and matches against the renamed bUn constant.
```

**Activity shape** (expected `userInfo`) — unchanged from 1.3883:

```js
{
  v: 1,
  sessionId: "cse_abcd1234",       // accepts full "cse_<id>" or bare alphanumeric
  organizationId: "<org-uuid>"
}
```

**Routing:**

- If a local Claude Code desktop session has been imported/bridged with matching `bridgeSessionId` → focus `/epitaxy/<localId>` (opens the bridged local session).
- Otherwise → navigate to `/code/<sessionId>`. The Code sub-window then loads this path via the normal Code-tab renderer (not the `window.open` blank-page path that URL-scheme `claude://claude.ai/code/...` hits).

**Caveats:**

- **Feature flag.** `xt("2049450122")` (was `Ii(...)` in 1.3883) returns false when GrowthBook hasn't enabled the flag for the user. If off, the handler logs "handoff: feature disabled, ignoring continuation" and returns. Can't tell from outside whether the flag is on for a given user — attempting the handoff and watching for navigation is the only signal.
- **Cold start handling.** If Claude.app isn't already running when the activity fires, the payload is stashed and replayed after the main view is ready. So seshctl should activate Claude.app and post the activity; the app handles ordering internally.
- **Validation is loose.** `sessionId` only needs to match `^[A-Za-z0-9_-]+$` — so either `cse_<id>` or the bare `<id>` suffix works. The claude.ai web URL uses `session_<id>` with the same underlying ID; either prefix passes the regex but `findSessionIdByBridgeSessionId` may only match the `cse_*` form depending on how `bridgeSessionId` is stored.
- **Rejection logging (new in 1.5220).** Bad payloads are now logged with structured `R.warn("handoff: ignoring activity with …")` lines in `~/Library/Logs/Claude/main.log` — useful for debugging if the activity does deliver but is rejected.

**How to post it from another Mac app (Swift):**

```swift
// NOTE: activity type renamed in v1.5220. Use the new string.
let activity = NSUserActivity(activityType: "com.anthropic.claude.code.session")
activity.userInfo = ["v": 1, "sessionId": "cse_<id>", "organizationId": "<org-uuid>"]
activity.isEligibleForHandoff = true
activity.becomeCurrent()
// then activate Claude.app via NSWorkspace.openApplication
```

**Empirically verified to NOT deliver same-device (against v1.3883, 2026-04-22).** Standalone Swift script posted the activity, retained it for 8s, activated Claude.app via `NSWorkspace.openApplication(at:configuration:)`. Claude.app cold-launched but `continue-activity` never fired (`~/Library/Logs/Claude/main.log` showed no handoff log line, and `GFt`/`hei` logs unconditionally on entry, including the "feature disabled" branch — so silence means the OS never delivered the activity to the receiving app's NSApplicationDelegate). Not re-tested against v1.5220; the limitation is in macOS, not Claude.app, so the conclusion is expected to hold. If you re-test, remember to use the new activity type `com.anthropic.claude.code.session`.

This matches the Apple-platform model for `NSUserActivity`: it is designed for **cross-device** Handoff via iCloud/Continuity, where the receiving user clicks a Handoff indicator that macOS surfaces (Dock glyph, lock screen tile). There is no public API for "deliver this activity to a specific peer app on the same Mac." If the activity originated on iOS Claude or another Mac signed into the same Apple ID, the receiving Claude.app on this Mac would fire `continue-activity` correctly — that's the intended path.

For seshctl's same-device use case: there is no working path. Stick with `RemoteClaudeCodeSession.webUrl` (browser fallback). The seshctl prototype (`ClaudeAppHandoff.swift`) was reverted after this empirical confirmation; see git history if you need to revisit.

## Remote Code-tab session focus via URL (still broken in 1.5220)

### `claude://claude.ai/code/session_<suffix>` → blank white window (unchanged since 1.3561)

1. `dEe` (was `qne`) routes host=`claude.ai`, first path segment = `code`. `DE.Code` (was `QE.Code`) exists in the subroute enum but is NOT handled in the inner `switch (o)` — falls through to `default` → `dispatchHandleDeepLink("https://claude.ai/code/session_<suffix>")` sends IPC to the main window renderer.
2. The renderer calls `window.open(...)` or equivalent for `/code/...` URLs.
3. `setWindowOpenHandler` special-cases `/code/*` via predicate `FpA` (was `cQA` in 1.3883, `FBA` earlier):

    ```js
    FpA = e => e.pathname.split("/")[1] !== DE.Code ? false
            : jf(e.host) || YUn.has(e.host);
    // YUn = Set(["claude.ai", "claude.com", "preview.claude.ai", "preview.claude.com"])
    ```

4. If no existing Code window → Electron spawns a fresh 850x700 `BrowserWindow` with `mainView.js` preload, `loadURL`s the URL directly.
5. The Code sub-window doesn't reuse the main window's `/epitaxy` hydration path — it raw-loads whatever URL came from `window.open()`, which doesn't render Code-tab content. Blank white.

### `claude://claude.ai/local_sessions/<cse_id>` → "starting new session" fallback

Still falls through `DE.LocalSessions` to `loadURL(https://claude.ai/local_sessions/<cse_id>)`. `local_sessions` is the Cowork lane; the web router can't map `cse_<id>` to a Cowork session and falls back to "start new session". Unchanged since 1.3561.

### Why no URL-scheme path is likely to work for `cse_<id>`

Claude.app's internal session IDs remain desktop-assigned, not API-derived:

- CLI import: `local_<cliUuid>` (via `importCliSession`)
- Sessions-bridge `startChildSession`: `` `local_${randomUUID()}` ``
- Dittos: `local_ditto_<id>`

No `importRemoteSession` / `openRemoteSession` / direct `cse_` → local-id lookup exists **as a URL handler**. The new Handoff path (above) is the only supported way to resolve `cse_<id>` → focused Code-tab navigation.

## Code tab vs. "Cowork" terminology

Unchanged. What users see as the **Code tab** in Claude.app corresponds to:

- `sidebarMode` enum values: `"chat" | "code" | "task" | "epitaxy" | "operon"`
- Internal path: `code → epitaxy` (explicit map `E === "code" ? "epitaxy" : E` at window-load time)
- Session route: `/epitaxy/<internalId>`
- Predicate: `UUi(url)` = `pathname === "/epitaxy" || startsWith("/epitaxy/")`

**Cowork** is a separate session class (`getFocusedSessionRoute(A === "cowork")` → `/local_sessions/<id>`), not the Code tab. The `claude://cowork/new` URL and the `/local_sessions/` path are both Cowork-specific.

## Gotchas

- **macOS full-screen bug** ([anthropics/claude-code#22691](https://github.com/anthropics/claude-code/issues/22691)): `claude://` callbacks don't foreground the app when a browser is in macOS native full-screen mode. Workaround: exit full screen before invoking.
- **Third-party custom-scheme passthrough** ([#26952](https://github.com/anthropics/claude-code/issues/26952)): Electron shell blocks outgoing clicks on third-party custom URL schemes. Doesn't affect `claude://` itself.
- **Windows OAuth forwarding** ([#31476](https://github.com/anthropics/claude-code/issues/31476)): Windows Store installs spawn new processes instead of forwarding. Irrelevant on macOS.
- **GrowthBook handoff gate**: Remote-session Handoff is behind feature flag `"2049450122"` (added 1.3883, still gated in 1.5220). Implement a graceful fallback path (browser `webUrl`) for users whose Claude.app doesn't have it enabled.

## Applying to seshctl

In `Sources/SeshctlUI/SessionAction.swift` (the routing entry point for Enter on a row):

- **Local CLI session row** → build `claude://resume?session=<cliUuid>` using the CLI session UUID captured by seshctl's `SessionStart` hook. Invoke via `NSWorkspace.shared.open(url)`. Idempotent.
- **Remote Code session row** → use `RemoteClaudeCodeSession.webUrl` (browser fallback) via `SessionActionTarget.openRemote(URL)`. **No working same-machine deep-link to focus a specific remote `cse_<id>` session in Claude.app exists.** All candidates were ruled out empirically on 2026-04-22 (against v1.3883) and re-checked structurally against v1.5220 on 2026-04-29 — no new URL-scheme path was added:
    - `claude://claude.ai/code/session_<id>` → blank Code sub-window (broken since 1.3561 and earlier)
    - `claude://claude.ai/claude-code-desktop/code/<cse_id>` → blank sub-window (same path)
    - `claude://claude.ai/claude-code-desktop/<cse_id>` → default Code tab, ID ignored
    - `claude://claude.ai/claude-code-desktop/?session=<cse_id>` → default Code tab (query stripped by shell's whitelist)
    - `NSUserActivity` Handoff → never fires `continue-activity` for same-device peer-process delivery
    - AppleScript / Apple Events / local IPC surface → none exists (no `sdef`, no custom AE handlers, no persistent local server)
- **Future option** — file feedback with Anthropic for a `claude://code/resume?session=<cse_id>` URL-scheme parity handler. The internal `dispatchNavigate('/code/${sessionId}')` already does the right thing — they'd just need a public route to reach it.

## How to re-verify on a new Claude.app version

```bash
# 1. Confirm scheme + Handoff activity type are still registered
plutil -p /Applications/Claude.app/Contents/Info.plist \
  | grep -A3 -E 'CFBundleURLSchemes|NSUserActivityTypes'

# 2. Extract app.asar (requires Node ≥22.12; asdf 22.22.2 works, 22.2.0 does not)
ASDF_NODEJS_VERSION=22.22.2 npx @electron/asar extract \
  /Applications/Claude.app/Contents/Resources/app.asar \
  /tmp/claude-asar-extracted

# 3. Beautify — makes the single-line minified bundle grep-able
ASDF_NODEJS_VERSION=22.22.2 npx js-beautify \
  /tmp/claude-asar-extracted/.vite/build/index.js \
  -o /tmp/claude-asar-extracted/index.pretty.js

# 4. Find the open-url handler (minified name drifts; search by string literal)
grep -n 'setAsDefaultProtocolClient("claude")' \
  /tmp/claude-asar-extracted/index.pretty.js

# 5. Find the top-level and subroute enums (stable string literals)
grep -n 'e.Hotkey = "hotkey"' /tmp/claude-asar-extracted/index.pretty.js
grep -n 'e.OpenConversation = "chat"' /tmp/claude-asar-extracted/index.pretty.js

# 6. Find the Handoff activity type — string has changed across versions
#    (1.3883: "com.anthropic.claude.session", 1.5220: "com.anthropic.claude.code.session"),
#    so search for the family with a regex.
grep -nE 'com\.anthropic\.claude(\.[a-z]+)*\.session' /tmp/claude-asar-extracted/index.pretty.js
```

Key symbols to trace in `index.pretty.js` (likely to drift between versions — re-identify by call graph, not name; arrows show 1.3883 → 1.5220):

- **`dEe(url, webContents)`** (was `qne`, `Ine` earlier) — top-level `claude://` handler, switch on `t.host`
- **`ZR`** (was `SR`, `AL` earlier) — top-level hosts: `hotkey, login, claude.ai, preview, cowork, code, debug-handoff`
- **`DE`** (was `QE`, `Bu` earlier) — `claude.ai/<subroute>` values, including `Code`/`Resume`/`LocalSessions`/`ClaudeCodeDesktop`
- **`pKA`** (was `f2A`, `V1A` earlier) — UUID regex
- **`wKA`** (was `m2A`, `j1A` earlier) — pass-through `loadURL` for known-but-unhandled subroutes
- **`vL`** (was `gb`, `rb` earlier) — dispatches `navigate` IPC, falls back to `loadURL`
- **`Ys.importCliSession(uuid)`** (was `no.importCliSession`, `Ko.importCliSession` earlier) — idempotent CLI import, returns `local_<uuid>`
- **`Ys.getSessionRoute(id)`** — returns `` `/epitaxy/${encodeURIComponent(id)}` ``
- **`Ys.findSessionIdByBridgeSessionId(cseId)`** — bridge-session lookup for Handoff
- **`FpA(url)`** (was `cQA`, `FBA` earlier) — predicate: is this a `/code/*` URL that needs the Code sub-window?
- **`PUn`** (was `OLr`, `qbr` earlier) — Code window accessor (find existing Code BrowserWindow)
- **`OUn`** (was the previous registration helper) — marks a window as the Code window via `WeakSet`
- **`YUn`** (was `PLr`) — `Set` of allowed Code-host strings (`claude.ai`, `claude.com`, `preview.*`)
- **`hei`** (was `GFt`) / **`UUn`** (was `GLr`) / **`LUn`** (was `bLr`) — Handoff dispatcher / payload validator / feature flag gate
- **`bUn = "com.anthropic.claude.code.session"`** (renamed in 1.5220 from `kLr = "com.anthropic.claude.session"`) — Handoff activity type constant. **Must match the Info.plist `NSUserActivityTypes` entry.**
- **`xt(flagId)`** (was `Ii`) — GrowthBook `isFeatureEnabled` helper
- **`It(eventName, props)`** (was `mt`) — telemetry helper
