# Plan: Remote Claude Code Sessions (claude.ai-hosted)

**Related**: `.agents/plans/2026-04-14-1600-remote-peer-session-visibility.md` covers sessions running on the user's *other machines* via SSH. This plan is a different axis — sessions running in **Anthropic's cloud** (the ones created via `claude.ai/code`, aka Cowork). Both can coexist; a "remote" session in seshctl may originate from a peer host or from the cloud.

## Why

Julian creates Claude Code sessions from the web UI at `claude.ai/code`. Those sessions (ids like `cse_014Mb5gbVpTMBVhPVNPFcYrz`) run in Anthropic-managed containers against GitHub repos. Today they are only visible in claude.ai's tab. seshctl already aggregates local session state across terminals; extending it to show cloud-hosted Claude Code sessions gives one place to see "everything I have in flight."

## Scope (MVP)

- List cloud Claude Code sessions in the existing session panel, visually marked as remote.
- `Enter` on a remote row opens `https://claude.ai/code/session/<id>` in the default browser.
- Poll every ~30s while the panel is visible; no background daemon.
- One-time sign-in flow inside seshctl; persistent auth with silent refresh.

Out of scope: creating sessions, sending messages, streaming events, archiving/deleting, tool-confirm UX. Read-only dashboard.

## API (what we observed)

Endpoint used by the claude.ai SPA:

```
GET https://claude.ai/v1/code/sessions?limit=50
Headers:
  cookie: sessionKey=...          # required, HttpOnly on claude.ai
  anthropic-beta: managed-agents-2026-04-01
  anthropic-version: 2023-06-01
```

Response shape (trimmed):

```json
{
  "data": [
    {
      "id": "cse_014Mb5gbVpTMBVhPVNPFcYrz",
      "title": "assistant",
      "status": "active",
      "worker_status": "running",
      "connection_status": "connected",
      "created_at": "2026-04-18T00:36:02Z",
      "last_event_at": "2026-04-19T03:11:54Z",
      "unread": true,
      "config": {
        "model": "claude-opus-4-7[1m]",
        "sources": [{"type": "git_repository", "url": "https://github.com/julo15/assistant", "revision": "main"}]
      },
      "external_metadata": {"current_branches": {"julo15/assistant": "main"}}
    }
  ]
}
```

**Stability risk**: this is an undocumented internal API. Anthropic ships `api.anthropic.com/v1/sessions` as a documented Managed Agents API, but that is a *different resource class* (`ses_*` via API key) — it does not list Claude Code / Cowork sessions. Accept the coupling; design for swap-out.

## Auth: WKWebView + Keychain

Native macOS app can't use a browser extension's cookie-sharing trick, but it has the next-best thing: embed WebKit.

1. **First run**: user clicks "Connect Claude Code" in seshctl settings. A sheet opens with a `WKWebView` pointed at `https://claude.ai/login`. User completes normal login (Google OAuth or magic link).
2. **Cookie capture**: on successful navigation to `claude.ai/code`, read `sessionKey` from the view's `WKHTTPCookieStore` and store in macOS Keychain under service `com.seshctl.claude-ai`. Dismiss sheet.
3. **Silent refresh**: keep a single hidden `WKWebView` pinned to `claude.ai` for the app lifetime. Before each fetch, re-read `sessionKey` from the view's cookie store — the browser-native machinery handles server-side rotations transparently. Persist back to Keychain on change.
4. **Hard re-auth (~monthly)**: on first 401, show a non-blocking banner in the session panel: "Claude Code sign-in expired — reconnect." Clicking re-opens the sheet. Until reconnected, remote rows are hidden (or marked stale, see below).

Why this is acceptable UX: one click every ~27 days. No DevTools, no terminal copy-paste, no config file editing.

## Data model

New file: `Sources/SeshctlCore/RemoteClaudeCodeSession.swift` — kept separate from `Session` rather than overloading it.

```swift
public struct RemoteClaudeCodeSession: Codable, Sendable, Identifiable, Equatable {
    public var id: String                      // e.g. "cse_..."
    public var title: String
    public var model: String
    public var repoUrl: String?                // from config.sources[0].url
    public var branch: String?                 // from external_metadata.current_branches (first value)
    public var status: String                  // raw "active" / "archived" / ...
    public var workerStatus: String            // "running" / "idle" / ...
    public var connectionStatus: String        // "connected" / "disconnected"
    public var lastEventAt: Date
    public var createdAt: Date
    public var unread: Bool
    public var webUrl: URL { URL(string: "https://claude.ai/code/session/\(id)")! }
}
```

**Persistence**: store in the existing GRDB database as a new table `remote_claude_code_sessions`, keyed on `id`. Upsert on each fetch. Don't merge into the `sessions` table — the schemas diverge (no `pid`, no `directory`, no `transcript_path`) and keeping them separate avoids nullable-field sprawl.

The *view model* is where local `Session` and `RemoteClaudeCodeSession` get unified into a single display type for the list view.

## Fetching

New file: `Sources/SeshctlCore/RemoteClaudeCodeFetcher.swift`.

```swift
public protocol RemoteClaudeCodeAuth {
    func cookieHeader() async throws -> String
    func invalidate() async
}

public actor RemoteClaudeCodeFetcher {
    private let auth: RemoteClaudeCodeAuth
    private let session: URLSession
    private let db: Database

    public func refresh() async throws {
        let (data, response) = try await session.data(for: request())
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            await auth.invalidate()
            throw RemoteClaudeCodeError.needsReauth
        }
        let decoded = try JSONDecoder.claude.decode(ListResponse.self, from: data)
        try await db.upsertRemoteClaudeCodeSessions(decoded.data)
    }
}
```

The `RemoteClaudeCodeAuth` protocol is the swap point: day-one implementation is `WKWebViewCookieAuth`; if Anthropic later ships an API key-based list endpoint for Claude Code sessions, drop in `APIKeyAuth` without touching the fetcher or UI.

**Polling cadence**: 30s while panel visible, paused when hidden. Reuse the existing panel-visibility signal that drives local refresh.

## UI

Minimal new surface area:

- **`SeshctlUI/RemoteClaudeCodeRowView.swift`** — renders repo + title + worker-status badge. Reuses `SessionRowView`'s layout primitives (avoid duplicating the row chrome).
- **`SessionListViewModel`** — add a second source that publishes `[RemoteClaudeCodeSession]` alongside the existing local sessions stream. Merged list is sorted by `lastEventAt` / `updatedAt` interleaved.
- **`SessionAction`** — add `.openRemote(URL)` case. `Enter` on a remote row dispatches `NSWorkspace.shared.open(session.webUrl)`.
- **Kill key (`x`)** — disabled for remote rows in MVP. Future: POST to archive.
- **Tree view grouping** — remote sessions group under a synthetic "☁️ claude.ai/code" group, same mechanism as directory groups.
- **Sign-in state banner** — renders at top of panel when auth is invalid or missing. Single line with a "Connect" button.

## Settings

Add a "Claude Code (claude.ai)" section to the existing seshctl settings pane:
- Connection status (connected / disconnected / error + date of last successful fetch).
- "Reconnect" button → opens the WKWebView sheet.
- "Disconnect" button → clears Keychain entry + drops cached sessions from DB.

## Testing

- Unit tests for response parsing against fixture JSON captured from a real session list (store in `Tests/SeshctlCoreTests/Fixtures/claude_code_sessions_list.json`).
- Integration test that swaps `RemoteClaudeCodeAuth` for a stub returning a fixed cookie and points `URLSession` at a local HTTP mock. Verifies 401 path invokes `invalidate()`.
- UI snapshot test for `RemoteClaudeCodeRowView` in the main row states (running / idle / disconnected / unread).

Do not write a test that hits claude.ai live.

## Rollout steps

1. `RemoteClaudeCodeSession` model + GRDB migration for `remote_claude_code_sessions` table.
2. `RemoteClaudeCodeFetcher` + `RemoteClaudeCodeAuth` protocol + stub auth impl for tests.
3. `WKWebViewCookieAuth` — the sign-in sheet + hidden silent-refresh view + Keychain glue.
4. Settings pane section + connect/disconnect actions.
5. `SessionListViewModel` integration: merged stream + sign-in banner.
6. `RemoteClaudeCodeRowView` + tree-view group + `Enter`-opens-URL action.
7. Fixture + unit + snapshot tests.

Each step is independently shippable; order matters because later steps consume earlier types.

## Risks & open questions

- **Cookie-store access from WKWebView**: verify that `WKHTTPCookieStore.getAllCookies` returns the `HttpOnly` `sessionKey`. It should (WebKit hands them to the native layer even though they're invisible to page JS), but confirm on first spike.
- **SameSite=Lax on `sessionKey`**: requests from a native `URLSession` with a manually-attached `Cookie` header are fine — SameSite only affects browser-initiated cross-site navigations.
- **Anthropic breaks the endpoint or tightens auth**: accepted. `RemoteClaudeCodeAuth` protocol makes the swap cheap; the fetcher is ~80 lines.
- **Multi-org accounts**: the endpoint appears to use the currently-active org from the cookie (`lastActiveOrg`). If Julian ever has multiple orgs, add org-switching to the settings pane later.
- **Rate limiting**: unknown. Default to 30s poll; if we see 429s, back off with jitter.

## Size estimate

~300 lines of Swift total. Roughly: sign-in sheet (~80), cookie/keychain helper (~40), fetcher + models (~120), UI tweaks (~60). A weekend.
