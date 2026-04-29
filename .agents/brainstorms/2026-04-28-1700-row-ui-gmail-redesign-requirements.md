---
date: 2026-04-28
topic: row-ui-gmail-redesign
---

# Session Row UI Redesign (Gmail-Inspired)

## Problem Frame

The session list is the primary triage surface in seshctl — users open it and need to answer two questions fast:

1. **"Which sessions need me?"** — already well-served today. The colored status dot encodes urgency (orange = waiting/working) and the time label encodes recency. These signals don't need rework.
2. **"What is each session actually doing?"** — under-served today. The latest assistant message lives on line 2, while line 1 carries three competing identifiers (`repo · dir · branch`) that are mostly redundant during scanning. The right side spends ~80pt repeating the agent identity (`claude` / `codex` / `gemini`) as text next to an app icon that already conveys context.

Inspired by Gmail's `sender + preview` row pattern, the redesign keeps the urgency signals untouched and reorganizes the content axis: promote the freshest content to line 1, push the identifier triplet to a subtitle (with worktree disambiguation moving up to line 1's sender slot per R1), and reclaim right-side space by collapsing the agent text label into a corner badge — phased to validate badge legibility before the text label is removed.

**Identity-bet note:** this redesign moves seshctl visually from terminal-adjacent (monospaced identifier triplet, dense layout) toward inbox-client (sender + preview, scannable strip). The bet is that scannability matters more than terminal density for the target user. Worth naming so future redesigns can revisit if the bet doesn't pay off.

Affected views: `Sources/SeshctlUI/SessionRowView.swift`, `Sources/SeshctlUI/RemoteClaudeCodeRowView.swift`, `Sources/SeshctlUI/ResultRowLayout.swift`.

## Requirements

**Line 1 — Sender + Preview**

- R1. Line 1 must render `[sender][preview text]` in a fixed sender-column layout. The sender column encodes session identity, not just repo identity:
  - When `dir basename == repo name`: sender is the repo name alone.
  - When `dir basename ≠ repo name` (worktrees, renamed clones, dir without a recognizable repo): sender is `<repo> · <dir basename>`, with the dir basename in tertiary or accent color to visually separate it from the repo prefix.

  The sender column has a fixed width (~180pt — to be tuned during implementation against real session-DB distribution). When truncation is needed, preserve the disambiguating dir suffix: middle-ellipsize the repo prefix rather than tail-truncating the whole string. Preview text starts at the same x position on every row, producing a clean vertical scan line.
- R2. Preview text must drop the assistant-side `Claude:` / `Codex:` / `Gemini:` prefix that currently precedes replies. The user-side `You:` prefix in R3 is **retained** — it disambiguates a fallback prompt from an assistant reply, which the badge cannot distinguish. The prefix-drop in R2 reclaims ~50pt of preview width once R7 also lands (Phase 2). Agent identity comes from the corner badge (R8).
- R2a. **Preview text content rules** (apply to both R2 and R3 fallback content):
  - Use the first non-empty line of the source text (`lastReply` or `lastAsk`); never render a multiline reply spread across rows.
  - Backticks and inline code spans in the source render as plain text with backticks preserved (current behavior — the visual reference's `` `julo/share-omit-url-…` `` shows backticks visible). The preview slot is not a markdown-rendering surface.
  - Tail-truncate with ellipsis when the text exceeds the available slot width (no fixed character cap; let the rendered width drive truncation).
- R3. Line 1 preview content follows this priority order, falling through to the next when the current is empty:
  1. `lastReply` — assistant's reply, rendered without the agent prefix per R2.
  2. `lastAsk` — user's last prompt, rendered in italic + dimmer secondary color as `You: <lastAsk>`. Italic styling visibly distinguishes user-side prompts from assistant replies during scanning.
  3. Status hint — derived from `SessionStatus` per R4.

  "Empty" in this chain means nil or zero-length / whitespace-only — both fall through to the next priority.
- R4. When both `lastReply` and `lastAsk` are empty, line 1 must show a status hint derived from `SessionStatus`. Map every enum case so no row falls through unrendered: `Working…` (working), `Waiting…` (waiting), `Idle` (idle), `Done` (completed), `Canceled` (canceled), `Ended` (stale). Use the existing status semantics — do not invent new copy.

**Line 2 — Subtitle**

- R5. Line 2 must render the branch in accent color as the primary subtitle content. When `gitBranch` is nil (sessions started outside a git repo), line 2 falls back to the directory path in tertiary monospaced color, preserving the existing non-git-repo row behavior. (Dir disambiguation now lives in the sender slot per R1, so line 2 stays clean.)
- R5a. **Local/cloud/bridged trio glyphs** (existing behavior, relocated): when `showCloudAffordances` is true, line 2 is prefixed with one or both of `laptopcomputer` (local presence) and `cloud.fill` (remote presence) before the branch — preserving current semantics. The three observable cases:
  - **Local-only:** `💻 <branch>` (laptopcomputer alone)
  - **Bridged (local + claude.ai twin):** `💻 ☁️ <branch>` (both glyphs)
  - **Remote-only:** `☁️ <branch>` (cloud.fill alone — applies to remote rows per R11)

  The glyphs are tertiary-color and small — they decorate, they don't compete with the branch.
- R6. Line 2 typography must read as a subtitle, not as primary content: smaller weight or size than line 1, lower contrast. The branch keeps its accent color treatment from the current layout — color carries the "which branch" signal even at reduced size; weight does the demoting work.

**Right Side — Agent Badge**

- R7. **Phase 2 — text label removal (follow-up release).** The text-based tool label (`claude` / `codex` / `gemini` / `claude.ai`) currently rendered as a monospaced footnote in `ResultRowLayout` is removed. R7 does **not** ship in the same release as R8; it ships only after R8 has been in production long enough to validate that agent identity is reliably recognizable from the badge alone during routine scanning. If during the soak period the badge proves illegible at @1x, R7 is deferred or replaced with a slim text fallback. Reclaimed space goes to the preview slot.
- R8. **Phase 1 — corner badge introduction.** The host app icon (24pt) gains a small corner badge (~10pt, bottom-right) that encodes the agent. Each agent has a distinct colored monogram or mark:
  - Claude → orange `C`
  - Codex → green `X` (or recognizable Codex/OpenAI mark)
  - Gemini → blue `G` (or Gemini mark)

  In Phase 1 the badge sits **alongside** the existing text label; the label is the safety net while badge recognition is being validated. Final visual language (monogram letterforms vs. logo marks) is a design execution detail — see Outstanding Questions.
- R8a. The composite icon + badge must carry a single `accessibilityLabel` combining host app and agent — e.g., "Ghostty, Claude" / "Terminal, Codex" / "VS Code, Gemini" / "Globe, Claude" for remote. This resolves both the VoiceOver gap (the existing host app icon has no label) and the color-only-encoding concern for color-blind users in one stroke.
- R9. For remote claude.ai sessions (which have no host app), the globe icon currently used serves as the base icon and receives the same orange `C` corner badge. The badge system is uniform across local and remote rows. Note: the globe is a tinted SF Symbol, not a raster app icon — the badge composition primitive must work for both image types.

**Unread Treatment**

- R10. The existing `UnreadPill` must persist as the unread indicator but relocate from line 1 (where it currently sits next to identifiers) to the right side, immediately before the chevron. This preserves explicit unread semantics without competing with the new fixed-column line 1.

**Remote Rows — Variant Rules**

- R11. Remote (claude.ai) rows follow the same overall structure as local rows (sender column + preview on line 1, subtitle on line 2, badged icon on the right) with these substitutions, since `RemoteClaudeCodeSession` has no `lastAsk` / `lastReply` / `SessionStatus`:
  - **Sender column:** repo name extracted from `repoUrl` (existing extraction logic preserved). When `repoUrl` is nil, fall back to "Remote" as the sender placeholder.
  - **Preview slot (line 1):** the session `title` (e.g., "alice"). Remote sessions have no local conversation data, so R3 (italic `You:`) and R4 (status hint) do not apply. The title is rendered in the same primary style as a local `lastReply`, no italic.
  - **Subtitle (line 2):** the first entry of `branches` in accent color when present. When `branches` is empty, line 2 collapses entirely — the row becomes single-line. (No status-hint fallback for remote rows; remote status is conveyed by the existing inactive-row opacity treatment per R12.)
  - **Right side:** globe SF Symbol as base icon + orange `C` corner badge per R9. The remote-row `cloud.fill` glyph that currently sits adjacent to the title moves to the line-2 prefix slot per R5a (rendered as `☁️ <branch>`).
  - **Unread:** the `isUnread` derivation (combining `unread` flag + `lastReadAt`) drives the same pill placement as local rows (R10), no special case.

  The badge composition primitive (R8) must work for SF Symbols (tinted) as well as raster app icons — the only meaningful difference at this layer is the base image type.

**Preserved Elements**

- R12. The following row chrome must be preserved unchanged: status dot (left), time label (left), repo accent bar (left), chevron (right), section headers (`TODAY` / `YESTERDAY` / `OLDER` / `Recent` / `Semantic`), inactive-row opacity treatment.
- R12a. **Italic semantics live at the line-1 styling tier; stale rows dim at the row-opacity tier.** R3's italic `You: <lastAsk>` is a content-state signal (this is your prompt, not a reply) and applies even on a stale row. Inactive-row opacity (R12) applies as a row-level multiplier on top of whatever line 1 chose to render. The two coexist without conflict: a stale row showing R3's fallback reads as italic-and-dimmed; a stale row showing a real `lastReply` reads as regular-weight-and-dimmed.

## Success Criteria

Falsifiable, self-test-able after Phase 1 ships:

- **Content-axis triage:** in a 20-row mixed corpus from real session data, the user can identify what each session is doing (just-replied / waiting on me / working / idle) by reading line 1 alone for ≥18 of 20 rows. Failure mode: routinely needing to read line 2 to answer this.
- **Worktree distinguishability:** in a snapshot with 3+ sessions sharing a repo name (worktree-heavy workflow), the user can identify which session is which by line 1 alone — sender column encodes session identity, not just repo identity. Failure mode: row-1 collisions.
- **Repo name shape:** repo names of typical length (`icetype`, `qbk-scheduler`, `seshctl`, `compound-engineering`) all read cleanly without dominating the row; middle-ellipsis preserves the disambiguating dir suffix when truncation kicks in.
- **Remote-row coherence:** remote claude.ai rows feel like a coherent variant of local rows — same visual grammar, different base icon and content sourcing per R11 — rather than a separate layout.
- **Phase 2 readiness (badge recognition):** after the soak period, the user can identify agent kind (claude / codex / gemini) from the badge alone on ≥9 of 10 mixed-agent rows in a 1-second scan, without referring to the text label. Failure mode: still glancing at the text label to confirm. If the test fails, R7 is deferred or the badge is redesigned.
- **Phase 2 outcome:** the right side is visibly less busy than today — one icon (with badge) + chevron, with the unread pill appearing only when relevant.

## Scope Boundaries

- **Out of scope:** changing what data is captured per session (`lastAsk`, `lastReply`, `gitBranch`, etc. all stay as-is).
- **Out of scope:** changing section grouping logic (`TODAY` / `YESTERDAY` / `OLDER` / `Recent` / `Semantic` buckets stay as-is).
- **Out of scope:** changing the row's interaction model (Enter still routes through `SessionAction.execute()`, focus/resume behavior unchanged).
- **Out of scope:** changing left-side chrome (status dot, time label, repo accent bar) — visual identity here is preserved.
- **Out of scope:** redesigning the popover's header bar (`13 active · 5 remote`, search, etc.) or section headers.
- **Out of scope:** any change to how host app or agent kind is detected — this is purely a presentation change.

## Key Decisions

- **Fixed sender column over flowing layout, encoding session identity.** Long sender strings middle-ellipsize (preserving the disambiguating dir suffix) rather than tail-truncating, and worktree rows put their disambiguator on line 1 — so line-1-alone scanning works even in worktree-heavy workflows. A flowing Gmail-faithful layout fails when repo names vary widely; a tail-ellipsizing column fails when shared-prefix repos collapse to the same stem. Session-identity sender + middle-ellipsis sidesteps both.
- **Drop assistant prefix.** With the corner badge encoding agent identity, `Claude:` / `Codex:` / `Gemini:` in preview text is pure redundancy. Cutting it gains ~50pt of preview width — meaningful with a fixed sender column. The user-side `You:` prefix in R3 stays because the badge cannot distinguish "your prompt" from "agent reply" — the prefix carries content-state semantics, not agent identity.
- **Phase 1 vs Phase 2 split.** Three independent moves were considered: (1) line swap (preview to line 1, identifiers to subtitle), (2) prefix drop, (3) text-label removal in favor of badge. Bundling all three risks shipping unvalidated assumptions about badge legibility. Splitting (1)+(2)+badge-add into Phase 1 and label-removal into Phase 2 — gated on the badge proving itself in routine use — captures most of the readability win immediately while keeping the validated-or-revert option open. Phase 1 has near-zero rollback cost; Phase 2 inherits it only after Phase 1 has earned it.
- **User prompt as empty-state fallback.** Italicized `You: <lastAsk>` is more informative than a generic placeholder and more honest than a status word, because it tells the reader what the session is actually doing.
- **Folder disambiguator on line 1, not line 2.** The folder is only meaningful when it differs from the repo (worktrees, renamed clones), and that's exactly when it carries session identity. Promoting it to the sender slot (R1) makes worktree rows distinguishable on line 1 alone; demoting it to a line-2 conditional would silently regress the line-1-alone scan goal.
- **Keep UnreadPill, relocate it.** Bold-on-unread (Gmail-style) was considered but rejected: the explicit pill is more legible and survives at-a-glance scanning better. Far-right placement keeps it out of the new line 1 layout.
- **Corner badge over side-by-side icons or colored ring.** Tightest spacing for the agent identity. Legibility risk at ~10pt is real, so R7 (text label removal) is gated behind a Phase 2 release after R8 (badge add) ships and the badge proves itself in routine use. Phase 1 ships both the badge and the label together — the label is the safety net during validation. The "reclaim ~50pt of preview width" benefit is therefore deferred to Phase 2; Phase 1 is purely additive.

## Dependencies / Assumptions

- The `Session` model exposes `lastAsk` in addition to `lastReply`, written by independent hook paths. **Verified:** `Database.updateSession` (Database.swift:233-286) treats `ask` and `reply` as independent optional parameters — Claude Code's `UserPromptSubmit` hook writes `lastAsk` the moment a prompt is sent, while `Stop` writes `lastReply` only after the agent finishes. This produces a real, semantically meaningful window where `lastAsk` is set and `lastReply` is nil — exactly the case R3 targets. R4 covers the narrow window between session creation (both nil per Database.swift:211-212) and the first prompt.
- `SessionStatus` exposes the states needed for R4's status hints (`working`, `waiting`, `idle`, `completed`, `canceled`, `stale` per the row scan). Mapping each status to a single short string is a planning detail.
- Remote rows use `claude.ai` as their tool label and a globe icon today (per the row scan). R9 currently specifies orange `C` for all remote rows because claude.ai is today's only remote platform. If a future remote platform supports non-claude agents, the badge color/letter must follow the actual agent (matching local-row behavior), not the platform — the orange-`C` rule in R9 is a today-specific shorthand, not a platform binding.
- Existing `repo accent bar` width and color logic (`ResultRowLayout.swift` lines 37–41) is preserved — no interaction with the new layout.

## Visual Reference

The reference below depicts the **Phase 2 final state** (text label already removed). Phase 1 has an extra `claude` / `codex` / `gemini` text label between the preview slot and the host-app icon, sitting alongside the badge as a recognition safety net.

```
Today's row, real session:

●  1s   icetype              Shipped. `julo/share-omit-url-…` fast-forwarded ⌗ ›
        main                                                                 24pt+badge

●  20s  qbk-scheduler        Pushed (`4ceb41e`). PR #141 is updated.         ⌗ ›
        julo/waitlist                                                        24pt+badge

●  35s  seshctl · wt2        You: refactor the auth middleware to…           ⌗ ›
        julo/waitlist                                                 (italic, no reply yet)

●  36s  seshctl · fork       Working…                                        ⌗ ›
        julo/spike-x                                                  (no lastAsk either)

●  24m  assistant            alice                                           🌐 ›
        main                                                          (remote, globe+badge)

●  9h   dot-agents           All clean.                                      ⌗ ›
        main                                                            (read, dimmer)

Legend:
  ●         status dot (existing color semantics: working/idle/waiting/etc.)
  1s/20s    time label (existing)
  [col]     fixed sender column (~180pt, monospaced semibold) — repo name
            alone when dir basename == repo, else `repo · dir-basename`
            with the disambiguator suffix preserved through middle-ellipsis
  [text]    preview slot — tail-truncated, drops `Claude:`/`Codex:`/`Gemini:` prefix
  italic    user prompt fallback (R3) when no assistant reply yet
  ⌗ / 🌐    24pt host app icon (or globe for remote) with ~10pt corner badge for agent
  ›         chevron (existing)

Unread row appends a pill (•) just before the chevron — not shown above.
Repo accent bar (left of sender column) preserved unchanged.
```

## Outstanding Questions

### Resolve Before Planning

_(none — all product decisions are settled)_

### Deferred to Planning

- [Affects R1][Technical] Sender column width — 180pt is a starting point. Measure against real repo-name + worktree-suffix distribution in the user's session DB before locking. The middle-ellipsis truncation strategy (preserve disambiguator suffix) needs an implementation primitive that doesn't exist in stock SwiftUI — either a custom `Text` measurement view, or a manual truncation helper that splits at the ` · ` separator.
- [Affects R7, R8][Needs research] Phase 2 trigger criteria — define what "soak period validation passed" means concretely. Options: a fixed time box (e.g., 2 weeks of routine use), an explicit self-test ("identify the agent on 9/10 mixed-agent rows in 1s scan"), or "I never wished I could see the text label". Pick one before merging Phase 1 so Phase 2 has a clear go/no-go.
- [Affects R8][Needs research] Badge visual language — three plausible directions: (a) typographic monograms (orange `C`, green `X`, blue `G`) on colored circles; (b) tinted versions of actual product marks; (c) shape coding. Quick design pass — one mockup per agent at @1x and @2x to confirm legibility at ~10pt.
- [Affects R8, R9][Technical] Badge composition primitive — must work for both raster app icons (NSImage) and tinted SF Symbols (globe for remote). Some app icons have transparent corners or busy bottom-right areas; may need a subtle background ring around the badge for separation. Hover/focus state of the ring needs to track selection tint to remain visible against highlight backgrounds.
- [Affects R10][Technical] UnreadPill relocation requires a `ResultRowLayout` API change — currently the pill is rendered inside `mainContent`; moving it next to the chevron means extending `ResultRowLayout` with a trailing-accessory slot (e.g., `trailingAccessory: View`) or an `isUnread: Bool` parameter. Pick one during planning.
- [Affects R10][Technical] Pill ordering relative to badge: `... [badge-icon] [pill] [chevron]` vs `... [pill] [badge-icon] [chevron]`. Visual weight argues pill outside (closer to chevron); symmetry argues pill inside. Quick layout call.
- [Affects R6][Technical] Line 2 subtitle treatment — smaller font size, lower-contrast color, or both? Font-size change hurts long-branch legibility.
- [Affects R1][Technical] Minimum popover width and degraded-state behavior — at what width does the preview slot become too narrow to be useful? Either fix a minimum popover width below which the layout doesn't need to handle, or define a degraded mode (e.g., sender column shrinks proportionally below a threshold).
- [Affects all][Accessibility] Beyond R8a's `accessibilityLabel`, confirm Dynamic Type behavior — line 1's fixed sender column has to give if the user is at large text sizes, otherwise the preview slot disappears.

## Next Steps

`-> /ce:plan` for structured implementation planning.
