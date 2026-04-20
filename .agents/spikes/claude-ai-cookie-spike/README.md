# Claude.ai Cookie Spike

Throwaway SwiftPM executable that answers the two P0 assumptions in
`.agents/plans/2026-04-20-0928-remote-claude-code-sessions.md`:

- **(A)** Does `WKHTTPCookieStore.getAllCookies()` return the `HttpOnly` `sessionKey` cookie from a native WKWebView after an interactive claude.ai login?
- **(B-partial)** Does `GET https://claude.ai/v1/code/sessions?limit=1` work from a `URLSession` with the cookie attached, from a **fresh WebView session** (not Julian's existing Chrome)?

Rotation behavior (24h idle test) is a follow-up — this minimal spike only covers the fast questions.

## Run

```
cd .agents/spikes/claude-ai-cookie-spike
swift run CookieSpike
```

A WKWebView window opens at `claude.ai/login`. Sign in normally (Google OAuth or magic link). After the first `didFinish` that lands on claude.ai, the spike logs:

1. All cookies scoped to `claude.ai` — name, `isHTTPOnly`, `isSecure`, `expiresDate`, domain, path, truncated value
2. A focused assessment of the `sessionKey` cookie — whether `isHTTPOnly` is true and its measured lifetime in days
3. The HTTP response from `/v1/code/sessions?limit=1` — status, Content-Type, and the first 800 bytes of the body

## Verdict

- ✅ 200 + sessionKey has `isHTTPOnly = true` → plan is viable as written; proceed to Step 1.
- ❌ `sessionKey` missing or `isHTTPOnly = false` with no value → plan is non-viable; escalate.
- ❌ non-200 → endpoint is gated; check for missing headers, org selector, or beta-flag dependency.

## Cleanup

This directory is throwaway. Delete with `trash .agents/spikes/claude-ai-cookie-spike/` once the decisions are made and folded back into the plan.
