# Plan: Remote Claude Code Sessions (claude.ai-hosted)

## Spike findings (2026-04-20)

A throwaway WKWebView spike (`.agents/spikes/claude-ai-cookie-spike/`) resolved the load-bearing unknowns before committing to design. Empirical results:

- ✅ `WKHTTPCookieStore.getAllCookies()` **does** return the HttpOnly `sessionKey` cookie. HttpOnly access is not a blocker.
- ✅ `GET /v1/code/sessions?limit=1` returns 200 from `URLSession` when called with the cookies captured from the WebView and a set of headers the SPA sends.
- ✅ `sessionKey` lifetime is **28 days** (measured via `expiresDate`).
- ✅ `WKWebsiteDataStore.default()` persists cookies across process restarts — a fresh run picks up the cookies from a previous login without re-prompting. This means we do **not** need a hidden "silent-refresh" WebView; the data store itself is the persistence layer.
- ⚠️ Google OAuth (`Continue with Google`) is blocked inside embedded WebViews. Login must go through claude.ai's email / magic-link path. This is a UX constraint, not a viability blocker.
- ⚠️ The API requires the **full claude.ai cookie set** (`sessionKey`, `sessionKeyLC`, `lastActiveOrg`, `routingHint`, `cf_clearance`, `__cf_bm`, plus ~12 others). `sessionKey` alone returns 401.
- ⚠️ The API requires these request headers: `Origin: https://claude.ai`, `Referer: https://claude.ai/code`, a Safari-flavored `User-Agent`, `Accept: application/json`, plus the `anthropic-beta` / `anthropic-version` pair.
- ⚠️ Response shape differs from initial observation: `branches` live at `config.outcomes[].git_info.branches` (not `external_metadata.current_branches`); `data` is paginated via `next_cursor`; there are additional fields (`environment_id`, `environment_kind`, `tags`, richer `config.sources[]`).

These findings are baked into the plan below; the "Step 0 spike" entry in rollout steps is marked complete.

## Why

Julian creates Claude Code sessions from the web UI at `claude.ai/code`. Those sessions (ids like `cse_014Mb5gbVpTMBVhPVNPFcYrz`) run in Anthropic-managed containers against GitHub repos. Today they are only visible in claude.ai's tab. seshctl's product identity is to be the control center ("Finder") for all Claude sessions — a session index with gaps is a broken index. Extending seshctl to surface cloud-hosted Claude Code sessions preserves that promise.

## Scope boundary

seshctl aggregates sessions across exactly two axes:

1. **Local** — Claude Code / Codex / Gemini sessions on this Mac, populated by CLI hooks writing to the local SQLite DB.
2. **Cloud** — claude.ai-hosted Claude Code (Cowork) sessions, populated by this fetcher.

Out of scope for this and future revisions unless explicitly re-scoped: sessions on other machines via SSH, mobile Claude Code sessions, non-Code claude.ai chat sessions, API-driven Managed Agents (`ses_*`) sessions.

## Scope (MVP)

- List cloud Claude Code sessions in the existing session panel, visually marked as remote.
- `Enter` on a remote row opens `https://claude.ai/code/session/<id>` in the default browser.
- Poll every ~30s while the panel is visible; no background daemon.
- One-time sign-in flow inside seshctl via WKWebView. Cookies persist in `WKWebsiteDataStore.default()` for the cookie's natural lifetime (~28 days); re-auth only when the cookie expires or the API returns 401.

Out of scope: creating sessions, sending messages, streaming events, archiving/deleting, tool-confirm UX. Read-only dashboard.

## API (verified via spike)

Endpoint:

```
GET https://claude.ai/v1/code/sessions?limit=50
Headers:
  cookie: <full claude.ai cookie set>          # see below
  anthropic-beta: managed-agents-2026-04-01
  anthropic-version: 2023-06-01
  origin: https://claude.ai
  referer: https://claude.ai/code
  user-agent: <Safari UA string>
  accept: application/json
```

**Required cookies** (from `WKWebsiteDataStore.default().httpCookieStore.allCookies()` filtered to `claude.ai`):

- `sessionKey` (HttpOnly, ~28d) — the auth token
- `sessionKeyLC` (non-HttpOnly, ~28d) — timestamp the server pairs with `sessionKey`
- `lastActiveOrg` (non-HttpOnly, ~1y) — selects which org's sessions to list
- `routingHint` (HttpOnly, ~30d) — JWT used for backend routing
- `cf_clearance` (HttpOnly, ~1y) — CloudFlare bot-challenge completion
- `__cf_bm` (HttpOnly, ~30min) — CloudFlare bot-management rolling cookie
- Plus analytics / session cookies (`_cfuvid`, `_fbp`, `ajs_anonymous_id`, `__ssid`, `anthropic-device-id`, `intercom-*`, etc.) — include them all; the path of least resistance is to pass every `.claude.ai`-scoped cookie the WebView has.

Pass `sessionKey` alone → 401.

Response shape (verified against a real session):

```json
{
  "data": [
    {
      "id": "cse_018D8CwUgr4TUHtrq8cNgBvL",
      "title": "Investigate cron error rate check alert",
      "status": "active",
      "worker_status": "idle",
      "connection_status": "connected",
      "created_at": "2026-04-15T01:40:25.669139Z",
      "last_event_at": "2026-04-20T17:47:19.514469Z",
      "unread": false,
      "environment_id": "",
      "environment_kind": "bridge",
      "tags": [],
      "external_metadata": {},
      "config": {
        "model": "claude-opus-4-6[1m]",
        "sources": [
          {
            "type": "git_repository",
            "url": "https://github.com/julo15/qbk-scheduler",
            "revision": "main",
            "allow_unrestricted_git_push": true,
            "sparse_checkout_paths": []
          }
        ],
        "outcomes": [
          {
            "type": "git_repository",
            "git_info": {
              "type": "github",
              "repo": "julo15/qbk-scheduler",
              "branches": ["main"]
            }
          }
        ]
      }
    }
  ],
  "next_cursor": "MTc3NjcwNzIzOTUxNDQ2OTAwMHwzYTYxNTYyYy1lMmEwLTQwYzItYWU0Yy1jZTUzZjMzYTBkODU="
}
```

Two notes on the shape:

- Branches are at `config.outcomes[].git_info.branches` (an array). Earlier plan draft incorrectly had them at `external_metadata.current_branches`.
- `next_cursor` indicates pagination. MVP can ignore it and just fetch the first page (likely caps at 50 — the SPA's observed `?limit=50`), but the schema carries it.

**Stability risk**: this is an undocumented internal API. Anthropic's documented Managed Agents API (`api.anthropic.com/v1/sessions`) is a different resource class (`ses_*` via API key) and does not list Claude Code / Cowork sessions. Accept the coupling.

## Auth: WKWebView + WKWebsiteDataStore

Native macOS app can't read Safari's cookies directly, but it has the next-best thing: embed WebKit and let it manage its own authenticated session. The key insight from the spike is that `WKWebsiteDataStore.default()` is itself a durable cookie store — the plan does not need a separate Keychain layer or a background refresh mechanism for the common case.

1. **First run**: user clicks "Connect Claude Code" in seshctl settings. A sheet opens with a `WKWebView` pointed at `https://claude.ai/login`. The WebView uses `customUserAgent` set to a current Safari string so Google's embedded-view check is a non-concern. The user logs in using **email + magic link** (Google OAuth is blocked by Google inside embedded WebViews — this is the one meaningful UX constraint from the spike). The sign-in sheet includes a URL bar or similar affordance so the user can paste the magic link URL back into the WebView (clicking the link in Mail.app would open it in their default browser and miss our WebView).
2. **Session capture** (automatic): `WKWebsiteDataStore.default()` persists every `.claude.ai`-scoped cookie the login flow sets — including `sessionKey`, `sessionKeyLC`, `lastActiveOrg`, `routingHint`, `cf_clearance`, `__cf_bm`, and analytics cookies. No explicit extraction or Keychain write is required at capture time. Dismiss the sheet on successful navigation to `claude.ai/code` (or any post-login claude.ai URL).
3. **Each fetch**: call `WKWebsiteDataStore.default().httpCookieStore.allCookies()`, filter to `.claude.ai` domain, build the `Cookie` header from all of them. Attach the required request headers (see API section). Issue the request via a fresh ephemeral `URLSession` with `httpShouldSetCookies = false` so no ambient cookie jar leaks.
4. **Re-auth on 401**: show a non-blocking banner in the session panel: "Claude Code sign-in expired — reconnect." Clicking re-opens the sign-in sheet. **Cached rows stay visible, marked stale, until reconnect.** Never hide rows on auth expiry — a silently-empty cloud group violates the Finder promise. On successful reconnect, invalidate the stale marker; the next fetch returns live data. (User-initiated Disconnect is different: it clears cookies from `WKWebsiteDataStore` AND drops cached rows immediately. See Settings.)

**Why this is simpler than the pre-spike plan**: the plan originally proposed a hidden persistent WebView for "silent cookie refresh." The spike confirmed that's unnecessary — WKWebsiteDataStore persists cookies across app lifetimes for their natural ~28-day lifetime, and the server uses those persisted cookies as-is without needing proactive rotation. On 401 we re-prompt; no timer, no background request.

**Why Keychain is optional**: cookies already live in WebKit's data store on disk. Migrating them to Keychain would add ~40 LOC and one Keychain API surface without obvious security benefit — an attacker with read access to the user's home directory can read either store. Defer Keychain until a concrete threat model requires it.

**Re-auth cadence is ~monthly** — `sessionKey`'s 28-day expiry is the driver. The "one click every ~27 days" UX claim from the pre-spike plan was correct; the spike just confirmed it empirically.

## Sign-in sheet UX

The sheet is the user's first (and monthly-after-first) interaction with the feature. Two unavoidable constraints from the spike shape its design:

- **Google "Continue with Google" is blocked** inside embedded WebViews by Google's OAuth policy. Clicking it yields claude.ai's generic "error logging you in" screen with no explanation.
- **The magic-link email's link opens in the user's default browser**, not our sheet. Clicking it completes auth in Safari; our sheet never sees the cookies.

The sheet's job is to prevent both failure modes with prominent guidance, and give the user a recovery path when they hit them anyway.

### Hosting

Standalone `NSWindow` (not a sheet attached to the floating panel), so hiding the panel via ⌘⇧S doesn't kill the sign-in flow. Window level `.modalPanel`. Dismissed only on explicit close or successful login detection. No click-outside-to-dismiss.

### Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Connect to Claude Code                                 [×] │
├─────────────────────────────────────────────────────────────┤
│ ⓘ  Use email to sign in — Google isn't supported here.      │
├─────────────────────────────────────────────────────────────┤
│ Paste magic-link URL:  [ https://claude.ai/magic?…     ] Go │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│            [ WKWebView at claude.ai/login ]                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

- **Title bar**: "Connect to Claude Code" + close button. Also used for the reconnect flow — title is the same.
- **Notice strip**: always visible. Copy: `ⓘ Use email to sign in — Google isn't supported here.` The `ⓘ` opens a popover explaining why (embedded-browser OAuth block) and instructing the user to right-click the magic-link in the email and copy the URL back into the sheet.
- **URL bar**: placeholder `Paste magic-link URL (right-click the link in your email → Copy Link Address)`. Accepts Enter or a Go button. No URL validation — paste garbage, WebView navigates to garbage, user recovers.
- **WebView**: fills the rest. Loaded with `claude.ai/login` on open. Safari `customUserAgent` set (same string as the fetcher uses).

### Sheet states

| State | Contents |
|---|---|
| Initial load | WebKit-default loading indicator inside WebView area; notice + URL bar visible |
| At login form (idle) | claude.ai's login form rendered; notice persists |
| Email submitted on claude.ai | claude.ai's "Check your email" screen — the key moment where the notice guidance is needed |
| User pasted magic-link URL | WebView navigates; brief spinner overlay |
| Login success detected | "✓ Signed in" flash toast; auto-dismiss after ~300ms |
| User clicked Google anyway | claude.ai's error page in WebView; notice strip stays prominent. No special intercept needed |
| WebKit navigation error (offline, DNS) | WebKit's default error page; URL bar remains usable for retry |
| User-closed mid-flow | Window disposes; panel state unchanged; any partial cookies in WKWebsiteDataStore are harmless (fetcher requires both `sessionKey` and `sessionKeyLC`) |

### Success detection

On every `didFinish` navigation:

1. If `webView.url?.host == "claude.ai"` AND `path.hasPrefix("/code")` — success.
2. If `httpCookieStore.allCookies()` contains both a `sessionKey` and `sessionKeyLC` cookie scoped to `.claude.ai` — success.

Either alone triggers the success flash + auto-dismiss. Both are belt-and-suspenders: (1) is the natural happy path; (2) catches cases where claude.ai redirects somewhere unexpected (e.g. `/new` instead of `/code`).

### Cancellation

Title-bar close, `Esc`, or `⌘W` all dispose the window. No confirmation. Panel state after cancel is whatever it was before.

### Non-goals for MVP

- No custom WebKit error UI (use defaults).
- No intercept of the Google-OAuth click — the persistent notice is the only prevention; if the user clicks anyway, claude.ai's error page + our notice speak for themselves.
- No state saved across cancellations.
- No support for accounts that can only sign in via Google (user must add a non-Google sign-in method on claude.ai's account settings first).
- No URL-bar validation or claude.ai allowlist — it accepts any URL as a convenience.

## Data model

New file: `Sources/SeshctlCore/RemoteClaudeCodeSession.swift` — kept separate from `Session` rather than overloading it.

```swift
public struct RemoteClaudeCodeSession: Codable, Sendable, Identifiable, Equatable {
    public var id: String                      // e.g. "cse_..."
    public var title: String
    public var model: String                   // from config.model
    public var repoUrl: String?                // from config.sources[0].url
    public var branches: [String]              // from config.outcomes[0].git_info.branches (flattened; usually 1)
    public var status: String                  // raw "active" / "archived" / ...
    public var workerStatus: String            // "running" / "idle" / ...
    public var connectionStatus: String        // "connected" / "disconnected"
    public var lastEventAt: Date
    public var createdAt: Date
    public var unread: Bool
    public var webUrl: URL { URL(string: "https://claude.ai/code/session/\(id)")! }
}
```

Fields ignored for MVP (present in response but unused): `environment_id`, `environment_kind`, `tags`, `external_metadata`, `config.sources[].allow_unrestricted_git_push`, `config.sources[].sparse_checkout_paths`. They can be added later without schema changes — the Codable decoder ignores unmapped fields.

**Persistence**: store in the existing GRDB database as a new table `remote_claude_code_sessions`, keyed on `id`. Upsert on each fetch. Don't merge into the `sessions` table — the schemas diverge (no `pid`, no `directory`, no `transcript_path`) and keeping them separate avoids nullable-field sprawl.

The *view model* is where local `Session` and `RemoteClaudeCodeSession` get unified into a single display type for the list view.

## Fetching

New file: `Sources/SeshctlCore/RemoteClaudeCodeFetcher.swift`.

```swift
public actor RemoteClaudeCodeFetcher {
    private let cookieStore: WKHTTPCookieStore  // from WKWebsiteDataStore.default()
    private let urlSession: URLSession          // ephemeral, httpShouldSetCookies = false
    private let db: Database

    public func refresh() async throws {
        let cookies = await cookieStore.allCookies()
            .filter { $0.domain.hasSuffix("claude.ai") }
        guard !cookies.isEmpty else { throw RemoteClaudeCodeError.notConnected }

        let cookieHeader = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        var req = URLRequest(url: URL(string: "https://claude.ai/v1/code/sessions?limit=50")!)
        req.setValue(cookieHeader,                   forHTTPHeaderField: "Cookie")
        req.setValue("managed-agents-2026-04-01",    forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01",                   forHTTPHeaderField: "anthropic-version")
        req.setValue("https://claude.ai",            forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai/code",       forHTTPHeaderField: "Referer")
        req.setValue(safariUserAgent,                forHTTPHeaderField: "User-Agent")
        req.setValue("application/json",             forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: req)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            throw RemoteClaudeCodeError.needsReauth
        }
        let decoded = try JSONDecoder.claude.decode(ListResponse.self, from: data)
        try await db.upsertRemoteClaudeCodeSessions(decoded.data)
    }
}
```

The fetcher depends directly on WebKit's cookie store — no protocol abstraction up front. One implementation behind an interface is speculative generality, and there is no second auth model in scope. If Anthropic later ships an API-key endpoint for Claude Code sessions, introduce the abstraction at that point under the existing code path; the fetcher is ~80 lines and the swap cost without a pre-built protocol is negligible.

**Polling cadence**: 30s while panel visible, paused when hidden. Reuse the existing panel-visibility signal that drives local refresh.

## UI

### Row treatment

Cloud sessions use the same row chrome as local `SessionRowView` — title on top, subtitle below, host badge on the right, timestamp aligned. The differences:

- **Left-edge glyph**:
  - `☁` for a normal cloud row (any `connection_status`/`worker_status` combo when `unread == false`)
  - `✦` in accent color when `unread == true` — this is the load-bearing "something's happening there" signal and should be visually distinct, matching how local unread works today
  - Glyph dimmed (muted color + italic title) when auth is expired and the row is stale
- **Subtitle**: `<repo-short-name> · <branch> · <secondary>` where `<secondary>` is `worker_status` when interesting (`running` / `disconnected`), omitted for `idle connected`.
- **Right-edge badge**: a small muted `claude.ai` text badge (mirrors the existing host-app badge position).
- **Timestamp**: `last_event_at` in the same relative format used for local sessions.

### Active-vs-recent split

Cloud sessions slot into the existing "Active" / "Recently active" split using **`connection_status == "connected"` as the active test** — any cloud session the server still considers alive goes in Active, regardless of `worker_status` or `unread`. Disconnected cloud sessions drop to Recently active, sorted by `last_event_at`. This matches the fact that Cowork sessions are long-lived (unlike ephemeral local terminals) — "alive in the cloud, ready to pick up" is the right threshold.

### Tree view grouping

**Cloud sessions join the existing repo group** that matches their `config.sources[0].url` → short repo name (e.g. `qbk-scheduler`). A cloud session for `github.com/julo15/qbk-scheduler` appears inside the same `qbk-scheduler` group as any local sessions for that repo. Local rows get the `●` glyph, cloud rows get `☁` / `✦`. This preserves the Finder framing — "everything I'm doing on qbk-scheduler in one place" — rather than isolating cloud sessions into a separate bucket.

A synthetic "Cloud — no repo" group exists as a fallback for cloud sessions whose `config.sources` is empty or doesn't include a git_repository source. Expected to be rare; MVP can leave this group hidden when empty.

### Banner + state machine

| App state | Banner | Cloud rows |
|---|---|---|
| Never connected | "Connect to Claude Code — **[Connect]**" | hidden |
| Connected, first fetch in flight | none (subtle spinner near the Cloud group header) | empty until fetch lands |
| Connected, steady state | none | live |
| Auth expired (401) | "Claude Code sign-in expired — **[Reconnect]**" | italicized + dimmed (stale) |
| Transient fetch error (5xx / network) | (inline treatment only on cloud rows, no global banner) | unchanged from last successful fetch |
| User-disconnected | "Connect to Claude Code — **[Connect]**" | cleared immediately from panel + DB |

### Actions

- **`Enter`** on a cloud row → `NSWorkspace.shared.open(session.webUrl)` via a new `SessionAction.openRemote(URL)` case. No terminal focus, no resume.
- **`x`** on a cloud row → silent no-op + one-time toast "Cloud sessions can't be killed yet" (shown the first time the user presses `x` on a cloud row, then suppressed). No kill affordance rendered on the row itself so there's no visual hint the verb exists.

### Files touched

- **`SeshctlUI/RemoteClaudeCodeRowView.swift`** (new) — reuses `SessionRowView`'s layout primitives; only the glyph + badge + action dispatch differ.
- **`SeshctlUI/SessionListViewModel`** — adds a `[RemoteClaudeCodeSession]` published source and a thin `DisplayRow` projection at the output surface (see "ViewModel refactor" section below for the design). Not a "tweak" — a real contained refactor, but bounded to this file and the view-layer call sites.
- **`SeshctlUI/SessionAction`** — adds `.openRemote(URL)` case.
- **`SeshctlUI/SignInBanner.swift`** (new) — the banner component.
- **`SeshctlUI/SettingsPopover.swift`** (new) — the popover content (state-dependent "Claude Code" section + "About" section).
- **`SeshctlUI/SessionListView.swift`** — adds the `ellipsis.circle` gear button to the header row and wires the keyboard shortcut.
- **`SeshctlUI/ClaudeCodeSignInSheet.swift`** (new) — the WKWebView sign-in sheet with the URL-bar affordance. Surfaces from both the banner and the popover.

## ViewModel refactor

`SessionListViewModel` is today typed end-to-end against `Session`. Naively merging `RemoteClaudeCodeSession` into the same `sessions` array would force ~15 computed properties and ~8 methods to switch on variants, cascade type changes into `SessionRowView` / `SessionTreeView` / `SessionListView`, and tangle the kill flow, search filter, and tree-grouping logic with cloud-specific semantics. A contained refactor is possible if the union type stays at the output surface, not the internal state.

### Approach: `DisplayRow` projection at the boundary

Keep internal state typed on `Session`. Add a parallel `@Published var remoteSessions: [RemoteClaudeCodeSession]`. Introduce a union only at the view-model output the views actually consume:

```swift
enum DisplayRow: Identifiable, Hashable {
    case local(Session)
    case remote(RemoteClaudeCodeSession)

    var id: String {
        switch self {
        case .local(let s):  return s.id
        case .remote(let r): return r.id
        }
    }
}
```

Cloud session IDs (`cse_*`) don't collide with local session UUIDs, so the unified `id` space works without a variant tag.

### Surface-by-surface changes

| Surface today | After |
|---|---|
| `@Published sessions: [Session]` | unchanged |
| (none) | **new** `@Published remoteSessions: [RemoteClaudeCodeSession]` |
| `activeSessions: [Session]` / `recentSessions: [Session]` (filter by `$0.isActive`) | **new** `activeRows: [DisplayRow]` / `recentRows: [DisplayRow]`. Cloud rows count as active iff `connection_status == "connected"`. Keep the old properties if they have other callers; else retire them. |
| `orderedSessions: [Session]` (`activeSessions + recentSessions`) | **new** `orderedRows: [DisplayRow]` |
| `filteredSessions` (searches 6 local fields) | **new** `filteredRows`: local rows match existing fields; `.remote` rows match `title`, repo short name, and `branches[]` (client-side only — no server-side search for remote) |
| `treeGroups: [SessionGroup]` keyed on `(primaryName, isRepo)` | Same key scheme. Remote rows compute `primaryName` from `config.sources[0].url` short name (e.g. `qbk-scheduler`) and `isRepo = true` when a git_repository source exists. Rows join the matching local group. Fallback "Cloud — no repo" synthetic group collects remote rows with no git source |
| `selectedIndex: Int` indexes `orderedSessions` | Indexes `orderedRows` instead. Sentinel `-1` semantics unchanged |
| `selectedSession: Session?` | Kept; returns the session only when `orderedRows[selectedIndex]` is `.local` (else `nil`). **new** `selectedRow: DisplayRow?` alongside it |
| `unreadSessionIds: Set<String>` | Same surface. Populated from two sources: local sessions via existing `updatedAt > lastReadAt` logic; remote rows directly from `remoteSession.unread` |
| `requestKill()` / `confirmKill()` | Guard at top: if `selectedRow` is `.remote`, silent no-op + one-time toast; if `.local`, existing logic unchanged |
| `markSessionRead(_ session: Session)` | Unchanged — local-only. For MVP, pressing `r` on a remote row is a silent no-op (see Decisions below) |
| `rememberFocusedSession(_ session: Session)` | Kept for local (used by kill-selection preservation). **new** `rememberFocusedRow(_ row: DisplayRow)` for the general case |
| Tree-mode toggle focus preservation (lookup by `.id` after reordering) | Same mechanism extends to `DisplayRow` — matches by `row.id` |
| Selection-move methods (`moveSelectionUp`/`Down`/`ToTop`/`ToBottom`/`By`, `jumpToNextGroup`/`jumpToPreviousGroup`) | Bounds now derived from `orderedRows.count`. No per-row-variant logic needed at this layer |
| `pendingKillSessionId` reset on move | Unchanged |
| `rememberFocusedSession` on row click / action | Replaced by `rememberFocusedRow` in most call sites; kept wherever a local-only Session reference is needed (e.g. markSessionRead) |
| Search blend with `recallResults` (selectedIndex overflow past `orderedSessions.count` into `selectedRecallResult`) | Same pattern — overflow threshold becomes `orderedRows.count`. `RecallResult` does **not** become a third `DisplayRow` variant; it stays in its own transient-search lane |

### Decisions this forces

1. **Mark-read on remote rows**: MVP = silent no-op. Rationale: we can't clear claude.ai's server-side unread flag (no write-back API in scope). Adding a local "dismissed unread" set keyed on `cse_*` would create a divergence between what seshctl shows and what claude.ai shows — not worth the complexity for MVP. Remote `unread` is purely read-through.

2. **Remote search fields**: `title`, repo short name, `branches[]`. Matches what's visible in the row. No server-side search.

3. **Row count / "X active" in the header**: include cloud rows in the count. The header label stays `"N active"` where N = `activeRows.count`.

### Blast radius

- `SessionListViewModel.swift`: ~120 LOC of additions + ~30 LOC of edits to existing computed properties. No method *signatures* change for local-session behavior.
- View-layer call sites (`SessionListView`, `SessionTreeView`, wherever a `Session` was iterated): swap to `DisplayRow` in the binding, switch on variant at the rendering point. ~30 LOC.
- `requestKill`/`confirmKill`: add a `.local`-guard at top, ~5 LOC each.

**Not touched**: `Session`, `Database`, `SessionAction.execute()` internals (dispatches on row variant at the caller, internal API unchanged), recall search, existing tests that operate on `[Session]` directly.

## Settings

seshctl has no settings surface today — the panel is intentionally chrome-less and there's no menu bar status item. This feature adds the first one, scoped to the minimum this feature needs:

### Gear button in the panel header

The panel's header row (currently "Seshctl" + "X active" count) gains a right-aligned `ellipsis.circle` SF Symbol button. Clicking opens a popover anchored to the button.

- Keyboard shortcut: `,` while the panel is focused (a single comma — matches the Mac-standard ⌘, convention without needing to involve the app's shortcut system). If that conflicts with anything existing, fall back to `⌘,`.
- The gear button is the only new chrome added to the panel header. Future settings can grow into the popover without further header changes.

### Popover content (MVP)

```
┌─────────────────────────────────────────────┐
│ Claude Code (claude.ai)                     │
│                                             │
│ State-dependent contents — see below        │
├─────────────────────────────────────────────┤
│ About                                       │
│ seshctl v<version>                          │
└─────────────────────────────────────────────┘
```

State-dependent "Claude Code" section by panel state:

| State | Contents |
|---|---|
| Never connected | `○ Not connected` · **[Connect…]** button |
| Connecting (sheet open) | `◐ Signing in…` · disabled Cancel |
| Connected, steady | `● Connected` + `Last fetch: 2m ago` · **[Reconnect]** · **[Disconnect]** |
| Connected, first fetch in flight | `● Connected` + `Fetching sessions…` · buttons disabled |
| Auth expired | `◐ Sign-in expired` + `Cached sessions showing stale data.` · **[Reconnect]** · **[Disconnect]** |
| Transient fetch error | `● Connected` + `Last fetch failed: <error>` · **[Retry]** · **[Reconnect]** · **[Disconnect]** |

Buttons:

- **Connect…** / **Reconnect** → opens the WKWebView sign-in sheet (see Auth section). Closes the popover first so the sheet has room.
- **Disconnect** → confirms with an inline confirmation ("Disconnect? Cached cloud sessions will be cleared."), then: clears `.claude.ai` cookies from `WKWebsiteDataStore.default()` + deletes cached rows from `remote_claude_code_sessions` table + transitions the panel to "Not connected." State update is synchronous (no waiting for a fetch cycle).
- **Retry** → forces an immediate fetch (bypasses the polling cadence), updates status text with the result.

### Relationship with the in-panel banner

The banner is a prominent surface for the two states where action is required (never-connected, auth-expired). The popover is the canonical control surface for all states including the idle ones. They don't conflict: the banner is a shortcut; the popover is the dashboard. Clicking Connect/Reconnect in either place opens the same sheet.

### Non-goals for MVP

- No login-path preference (we force email/magic-link; Google isn't an option in an embedded WebView).
- No poll cadence preference (30s is the only option for MVP).
- No multi-account / org switcher (see "Multi-org accounts" under Risks).
- No "show HTTPS debug log" or equivalent inspector surface.

## Testing

- Unit tests for response parsing against fixture JSON captured from a real session list (store in `Tests/SeshctlCoreTests/Fixtures/claude_code_sessions_list.json`).
- Integration test that swaps `RemoteClaudeCodeAuth` for a stub returning a fixed cookie and points `URLSession` at a local HTTP mock. Verifies 401 path invokes `invalidate()`.
- UI snapshot test for `RemoteClaudeCodeRowView` in each of these states: (1) connected + idle + read (base), (2) connected + running + read, (3) unread (accent glyph), (4) disconnected, (5) auth-expired / stale (dimmed + italic). These are the visual states the view model actually produces.

Do not write a test that hits claude.ai live.

## Rollout steps

0. ~~**Verification spike**~~ — ✅ done. See "Spike findings" at the top of this plan. Spike code lives at `.agents/spikes/claude-ai-cookie-spike/` and can be deleted once findings are consumed.
1. ~~`RemoteClaudeCodeSession` model + GRDB migration for `remote_claude_code_sessions` table.~~ ✅ done (migration v10).
2. ~~`RemoteClaudeCodeFetcher` — depends on a `WKHTTPCookieStore` reference from the shared `WKWebsiteDataStore.default()`.~~ ✅ done. Uses a `ClaudeCookieSource` protocol for testability; the production WebKit-based source is wired at the UI layer.
3. ~~Sign-in sheet (`ClaudeCodeSignInSheet.swift`) — standalone `NSWindow` with notice strip, URL bar, WKWebView. Safari `customUserAgent`. Auto-dismisses on success detection (path hasPrefix `/code` OR `sessionKey`+`sessionKeyLC` both present). See "Sign-in sheet UX" section for the full design.~~ ✅ done.
4. Panel header gear button + `SettingsPopover` containing the state-dependent "Claude Code" section (Connect / Reconnect / Disconnect / Retry). This is the first settings surface in seshctl.
5. `SessionListViewModel` refactor — add `remoteSessions` published source, introduce `DisplayRow` projection, migrate `orderedSessions` → `orderedRows`, extend filter/grouping/selection/unread/kill-guard to the union (see ViewModel refactor section). Update view-layer call sites accordingly.
6. `RemoteClaudeCodeRowView` + tree-view group + `Enter`-opens-URL action.
7. Fixture + unit + snapshot tests.

Each step is independently shippable; order matters because later steps consume earlier types.

## Risks & open questions

- **Google OAuth blocked in embedded WebView**: the login sheet must guide the user to the email/magic-link path. Needs first-class UX copy in the sheet ("use email — Google sign-in isn't supported inside seshctl") rather than letting the user click Google and hit claude.ai's generic "error logging you in" message.
- **Magic-link click opens default browser**: clicking the magic link in Mail.app navigates Safari (or whichever browser is default), not seshctl's WebView, so the login completes in the wrong process. Mitigation: provide a URL-bar affordance in the sign-in sheet and tell the user to right-click → Copy Link, paste into sheet.
- **`__cf_bm` rotates every ~30 minutes**: CloudFlare's bot-management cookie has a short lifetime. The spike succeeded with a `__cf_bm` that was ~28 minutes old, which suggests CloudFlare is not strict, but long-running scenarios may eventually hit a re-challenge. Mitigation if we see issues in practice: occasionally load `claude.ai/code` in the hidden or visible WebView to let CloudFlare rotate the cookie naturally. Not needed for MVP.
- **TLS fingerprint mismatch**: the request from `URLSession` has a different TLS/HTTP2 fingerprint than Safari's. Today CloudFlare appears not to fingerprint-match claude.ai requests; if it starts doing so, even a fresh cookie set could be rejected. No clean mitigation — would require either routing through the WebView (e.g. `evaluateJavaScript` with `fetch()`) or rethinking the architecture.
- **SameSite=Lax on `sessionKey`**: requests from a native `URLSession` with a manually-attached `Cookie` header are fine — SameSite only affects browser-initiated cross-site navigations.
- **Anthropic breaks the endpoint or tightens auth**: accepted. The fetcher is ~80 lines so rewriting for a replacement endpoint is cheap. The broader coupling — `cse_` id prefix, `/code/session/<id>` URL shape, `worker_status`/`connection_status` field names baked into the UI and DB — is worth acknowledging: the swap-out is only trivially cheap if the replacement has similar semantics. If the replacement is shaped differently, UI copy, row decoration, and tests also need updating.
- **Multi-org accounts**: the endpoint uses the currently-active org from the `lastActiveOrg` cookie. If Julian ever has multiple orgs, add org-switching to the settings pane later.
- **Rate limiting**: unknown. Default to 30s poll; if we see 429s, back off with jitter.

## Size estimate

~270 lines for the feature's own code — sign-in sheet with URL-bar affordance (~90), fetcher + models (~80), settings popover + gear button (~80), sign-in banner (~20). The ViewModel refactor to support remote-session rows alongside local `Session` values is tracked as a separate P1 finding and is realistically ~150 LOC of careful changes in `SessionListViewModel` — it's not "UI tweaks." The real maintenance cost is ongoing (header updates, response-shape drift, 401 edge cases, CloudFlare behavior changes); budget accordingly rather than treating this as a one-weekend build.
