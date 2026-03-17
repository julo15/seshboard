# Session Detail View

## Goal

A full-panel conversation viewer that opens with `o` on a selected session row.
Shows the complete back-and-forth transcript from Claude Code's local JSONL files.
Keyboard-first, vi-style navigation. Opens at the bottom (most recent).

## Architecture

`NavigationState` (observable) holds the current screen — `.list` or `.detail(vm)`.
`AppDelegate` conditionally renders either the list or detail view based on the
current screen. `AppDelegate` routes keyboard events to the right handler based
on which screen is active.

No new windows, no navigation stack — in-place swap within the same panel.

## Data Source

Claude Code stores transcripts at:
`~/.claude/projects/{encoded-path}/{conversationId}.jsonl`

`{encoded-path}` = directory path with `/` replaced by `-`, leading `/` dropped.
e.g. `/Users/foo/bar` → `-Users-foo-bar`

`conversationId` = `Session.conversationId` (set from `session_id` in SessionStart hook).

Each JSONL line has `type`: `user`, `assistant`, `progress`, `system`,
`file-history-snapshot`, `queue-operation`.

### JSONL structure (verified from real transcripts)

**Assistant messages** are streamed: same `message.id` appears across multiple lines,
each with a SINGLE content block. The blocks are NOT accumulated — each line has only
its own block. To reconstruct a complete response, **merge all entries with the same
`message.id`** by concatenating their `content` arrays.

Example for one assistant turn (`msg_01KFqqZfcqJx2DkGUfHA258b`):
```
Line 1: content = [{"type": "thinking", ...}]     stop_reason = null
Line 2: content = [{"type": "text", ...}]          stop_reason = null
Line 3: content = [{"type": "tool_use", ...}]      stop_reason = null
Line 4: content = [{"type": "tool_use", ...}]      stop_reason = null
Line 5: content = [{"type": "tool_use", ...}]      stop_reason = "tool_use"
```
→ Merge into one turn with [thinking, text, tool_use, tool_use, tool_use].

**User messages** come in two forms:
- `content` is a string → actual user prompt (37 of 91 in sample)
- `content` is an array with `tool_result` blocks → API plumbing, skip (53 of 91)
- `content` is an array with `text` blocks → user action like "[Request interrupted]" (1 of 91)

**Filter out:** `progress`, `system`, `file-history-snapshot`, `queue-operation` types.

**Strip from user messages:** `<system-reminder>...</system-reminder>` XML tags (injected
by Claude Code, noisy in a viewer).

**Thinking blocks:** Content is empty or contains encrypted signatures. Strip them.

### File sizes

Transcripts range from 72 lines to 1.5MB. Parsing must be async. Use `LazyVStack`
for the view to handle large conversations.

## New Files

| File | Purpose |
|---|---|
| `SeshboardCore/TranscriptParser.swift` | Reads `.jsonl`, merges by `message.id`, emits `[ConversationTurn]` directly. Also has `transcriptURL(for:)` to compute path from session. |
| `SeshboardCore/ConversationTurn.swift` | Display model: `.userMessage(text:timestamp:)` / `.assistantMessage(text:toolCalls:timestamp:)` with `ToolCallSummary` |
| `SeshboardUI/NavigationState.swift` | `screen: .list \| .detail(vm)`, `openDetail(for:)`, `backToList()` |
| `SeshboardUI/SessionDetailViewModel.swift` | Loads turns async, owns `scrollCommand: ScrollCommand?` |
| `SeshboardUI/SessionDetailView.swift` | Full-panel conversation view with NSScrollView-backed scrolling |
| `SeshboardUI/TurnView.swift` | `UserTurnView`, `AssistantTurnView`, tool call summary line |

### Why single-pass parsing (no TranscriptEntry intermediate)

The two-pass approach (JSONL → TranscriptEntry → ConversationTurn) adds an intermediate
model that isn't reused anywhere. Since the only consumer is the detail view, parse
directly into `ConversationTurn` in one pass: read lines → group by `message.id` for
assistant messages → emit turns.

## Changes to Existing Files

- **`AppDelegate.swift`** — add `NavigationState` property, add `@ViewBuilder` conditional
  in panel root (list vs detail), add `"o"` binding in list key handler, add
  `handleDetailKey` for all detail navigation keys, reset `pendingG` when opening detail.

## Keyboard Map (detail view)

| Key | Action |
|---|---|
| `j` / `↓` | Scroll down ~1 line (pixel-based) |
| `k` / `↑` | Scroll up ~1 line (pixel-based) |
| `Ctrl+D` / `Ctrl+U` | Half page down / up |
| `Ctrl+F` / `Ctrl+B` | Full page down / up |
| `G` | Jump to bottom |
| `gg` | Jump to top |
| `q` / `Esc` | Back to list |

Ctrl key combos: `chars` when Ctrl is held returns a control character —
`\u{04}` for Ctrl+D, `\u{15}` for Ctrl+U, `\u{06}` for Ctrl+F, `\u{02}` for Ctrl+B.

## Scroll Implementation

**Use NSScrollView pixel offsets, not turn-index-based scrolling.**

Turns vary wildly in height — a user prompt is 2 lines, an assistant response can be
50+. Turn-index scrolling ("jump 5 turns") would be janky. The `FloatingPanel` already
uses AppKit, so we access the underlying `NSScrollView` from the `NSHostingView` and
scroll by pixel deltas:

- `j/k` → scroll by ~20px (one line)
- `Ctrl+D/U` → scroll by `visibleHeight / 2`
- `Ctrl+F/B` → scroll by `visibleHeight`
- `G` → scroll to `documentView.frame.maxY`
- `gg` → scroll to top (0)

The `SessionDetailViewModel` publishes `scrollCommand: ScrollCommand?`. The view
consumes it, resolves to pixel offsets using the `NSScrollView` geometry, then clears it.

## Visual Design

- Monospaced font throughout (matches existing style).
- User turns: accent-tinted background, label like "You".
- Assistant turns: plain background, label like "Claude".
- Tool calls: single summary line per assistant turn, e.g. "Read x5, Edit x2, Bash x1".
  Per-tool input summaries are future scope — too fiddly for v1.
- Header: directory name | tool badge | status dot. Back hint.
- Opens at bottom: scroll to end on appear.

## Edge Cases

- No `conversationId` → show "No transcript available".
- Transcript file missing → show "No transcript available".
- Non-Claude tools (Gemini, Codex) → show "Transcript not available for {tool}".
- Active sessions → snapshot view (no live-reload in v1).
- `<system-reminder>` tags in user messages → strip them.
- `thinking` content blocks → strip (content is empty/encrypted).

## Tests

### TranscriptParserTests

1. `testEncodesPathCorrectly` — `/Users/foo/bar` → `-Users-foo-bar`
2. `testReturnsNilWhenNoConversationId` — session without conversationId → nil URL
3. `testParsesUserTextMessage` — string content → `.userMessage`
4. `testParsesAssistantMessage` — text content block → `.assistantMessage` with text
5. `testMergesContentBlocksByMessageId` — multiple lines with same id → merged into one turn with all blocks
6. `testFiltersProgressEntries` — progress entries dropped
7. `testFiltersToolResultUserMessages` — user messages with only tool_result → skipped
8. `testStripsSystemReminders` — `<system-reminder>` tags removed from user messages
9. `testStripsThinkingBlocks` — thinking blocks not included in output
10. `testToolCallSummary` — tool_use blocks → `ToolCallSummary` with name
11. `testEmptyFileReturnsEmpty` — empty file → empty array
12. `testChronologicalOrder` — turns sorted by timestamp

### SessionDetailViewModelTests

1. `testLoadPopulatesTurns` — loads from fixture JSONL
2. `testLoadSetsErrorOnMissingFile` — missing file → error set
3. `testScrollCommandClearedAfterSet` — set and clear cycle works

## Implementation Order

1. `ConversationTurn.swift` — model types
2. `TranscriptParser.swift` + `TranscriptParserTests` — parsing with tests
3. `NavigationState.swift` + `SessionDetailViewModel.swift` + tests
4. `TurnView.swift` + `SessionDetailView.swift` — UI
5. `AppDelegate.swift` wiring — keyboard routing, panel swap
