# Remote session differentiation — requirements

**Date:** 2026-04-22
**Status:** Ready for planning
**Related:** Remote Claude Code control integration (shipped via PRs ending in #19)

## Problem

After adding remote Claude Code control, the session list now shows three kinds of rows:

1. **Local-only** — no cloud presence.
2. **Bridged** — the same conversation exists both as a local terminal session and on claude.ai.
3. **Pure-remote** — only lives on claude.ai; no local terminal.

Bridged and pure-remote rows both render `cloud.fill` in the same position/color on line 2 (`Sources/SeshctlUI/SessionRowView.swift:71`, `Sources/SeshctlUI/RemoteClaudeCodeRowView.swift:94`). The only signals distinguishing them are the small host-app glyph and tool-name label on the right (`claude` + VS Code/iTerm icon vs `claude.ai` + globe). At a glance, the two row kinds read as the same thing.

## Goal

Let the user **understand their cloud footprint at a glance** — specifically, how many of their currently-visible sessions have a copy living on claude.ai — while also being able to tell, per row, whether a cloud-visible session has a local terminal they can jump into.

"Remote" is the user-facing term throughout. Do not use "exposed" or "cloud" in copy.

## Non-goals

- Re-working row layout broadly. This change stays inside the existing two-line row and the Seshctl header.
- Changing routing behavior (Enter on a bridged row still focuses the local terminal; Enter on a pure-remote row still opens claude.ai). `SessionAction.execute()` is untouched.
- Per-row tooltips beyond minor string tweaks to the existing `.help(...)` modifiers.
- Filtering, grouping, or hiding remote sessions. The counter is informational only for now.

## Decisions

### D1. Surface a remote-session counter in the Seshctl header

The popover/window header currently shows `Seshctl` on the left and `N active` on the right (plus the overflow menu). Add a compact "remote" tally next to `N active`, e.g.:

```
Seshctl                                15 active · 3 remote  ⋯
```

Styling: same type size/weight as `N active`, tertiary color. Include an `icloud` or `cloud.fill` glyph before the number to make the number instantly readable as a cloud metric. Hide the tally entirely when the count is zero (avoid dead chrome when the user has no remote sessions).

### D2. The "remote" count includes bridged sessions

Bridged sessions are in the cloud — the whole point of the counter is to reflect cloud footprint. A bridged session is functionally identical to a pure-remote one from a "is this conversation on claude.ai" perspective; the only difference is whether a local terminal happens to also be attached.

So: **count = (pure-remote rows) + (bridged local rows)**.

If a future requirement emerges to separate "only in cloud" from "also in cloud," we can split into two tallies then. For now, one number.

### D3. Differentiate bridged vs pure-remote rows with distinct line-2 glyphs

Freed from having to carry the "tally me" job (the header counter does that now), the per-row glyph can focus on row identity:

- **Pure-remote row** (`RemoteClaudeCodeRowView.subtitleRow`): keep `cloud.fill`, tertiary color. Reads as "this session only lives in the cloud."
- **Bridged local row** (`SessionRowView` line-2 marker, currently `cloud.fill` when `isBridged`): change to a "linked / synced" glyph — preferred: `arrow.triangle.2.circlepath`. Alternatives worth trying during implementation: `link`, `point.topleft.down.curvedto.point.bottomright.up`, `rectangle.connected.to.line.below`. Keep tertiary color and the same 11pt font size so the visual weight matches.
- `.help(...)` text updates accordingly: bridged says "Also running on claude.ai (Enter focuses the local terminal)"; pure-remote says "Runs on claude.ai only."

The concrete glyph pick is a small implementation-time decision — pick whichever reads cleanest at 11pt in both light and dark appearance.

### D4. Counter label copy

`N remote` (lowercase), matching the existing `N active` convention. Not `N cloud`, `N exposed`, or `N in cloud`.

## Success criteria

- Scanning the Seshctl popover header tells the user how many of their currently-listed sessions are on claude.ai, without scrolling the list.
- A user glancing at any single row can tell in under a second whether it's local-only, bridged, or pure-remote without needing to hover or read the right-side tool-name label.
- The counter matches what a manual count of `cloud`/`sync` glyphs in the list would produce — i.e., counter and row glyphs stay consistent.
- Zero remote sessions means no counter chrome is shown.

## Out-of-scope / follow-ups

- Making the counter clickable (e.g., filter list to remote-only). Defer until someone asks for it.
- Warning treatment (amber tint, etc.) when the remote count crosses a threshold.
- Distinguishing bridged-via-CLI-hook from bridged-via-other-source if that ever becomes a thing.

## Affected files (pointers for planning)

- `Sources/SeshctlUI/SessionRowView.swift` — bridged-row glyph swap.
- `Sources/SeshctlUI/RemoteClaudeCodeRowView.swift` — no change expected; pure-remote glyph stays `cloud.fill`.
- `Sources/SeshctlUI/SessionListView.swift` (or whichever view owns the popover header — planning to confirm) — add the counter.
- `Sources/SeshctlUI/SessionListViewModel.swift` — expose a `remoteSessionCount` (bridged + pure-remote).
- Tests: view-model test for the count, plus any snapshot/unit coverage on the row views.

## Implementation note (2026-04-22)

Final landed design diverges from D3:

- Bridged rows render `laptopcomputer` followed by `cloud.fill` on line 2.
- Local-only rows render `laptopcomputer` alone on line 2 (new — D3 implied no glyph on local-only rows).
- Pure-remote rows still render `cloud.fill` alone.
- All row-kind glyphs are gated on `ClaudeCodeConnectionStore.hasClaudeConnection`: when the user has not connected claude.ai, line 2 reverts to the pre-cloud layout (no glyph). The header counter is gated on the same predicate.

Rationale for the pivot: the `arrow.triangle.2.circlepath` approach made bridged rows distinct from pure-remote but still left local-only vs bridged as the primary visual question (bridged has a glyph, local-only doesn't). The three-way icon taxonomy makes every row's kind explicit and scannable, and the connection-gated behavior means users who aren't using claude.ai see no new chrome.
