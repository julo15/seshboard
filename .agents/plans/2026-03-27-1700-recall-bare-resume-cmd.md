# Plan: Return bare resume command from recall API

## Working Protocol
- Two repos: `../recall` (Python) and `.` (seshctl, Swift)
- Change recall first, then update seshctl consumers

## Overview
The recall API's `resume_cmd` field returns a compound shell command (`cd /path && claude --resume <id>`), but the `project` field already provides the directory. This forces consumers to parse out the `cd` prefix. Change recall to return just the bare command, and update seshctl to remove its regex workaround.

## Current State

**recall** (`../recall/recall/search.py:19-34`):
```python
def _resume_command(entry, *, skip_permissions=False):
    # builds "claude --resume <id>" etc.
    if entry.project:
        cmd = f"cd {entry.project} && {cmd}"  # <-- this is the problem
    return cmd
```

CLI display (`../recall/recall/cli.py:203`): `> {r.resume_cmd}` — shows the compound form.

**seshctl**:
- `SessionAction.swift:108-112` — regex strips `cd ... && ` prefix before passing to `TerminalController.resume()`
- `SessionListViewModel.swift:313` — `copyResumeCommand()` copies raw `resumeCmd` to clipboard
- `SessionAction.swift:118` — fallback clipboard copy uses raw `resumeCmd`

## Proposed Changes

### recall
1. Remove the `cd` prefix from `_resume_command()` — return bare command only
2. CLI display reconstructs compound form for human readability: `> cd {project} && {resume_cmd}`
3. Update AGENTS.md API contract docs

### seshctl
1. Remove regex workaround in `SessionAction.handleRecallResult()`
2. Update clipboard copies to construct compound form (`cd {project} && {resumeCmd}`) since users pasting into a terminal need the full command
3. Update test that validates the stripping behavior

### Complexity Assessment
Low. 2 files in recall, 2-3 files in seshctl. All changes are mechanical — no new patterns, no architectural risk.

## Implementation Steps

### Step 1: recall — return bare resume_cmd
- [x] `../recall/recall/search.py:31-32` — remove the `if entry.project: cmd = f"cd ..."` lines
- [x] `../recall/recall/cli.py:203` — change display to `> cd {r.entry.project} && {r.resume_cmd}` (only when project exists)
- [x] `../recall/AGENTS.md:93` — update API contract description
- [x] Run recall tests — 28/28 pass

### Step 2: seshctl — remove workaround, fix clipboard
- [x] `Sources/SeshctlUI/SessionAction.swift` — remove regex stripping, pass `result.resumeCmd` directly
- [x] `Sources/SeshctlUI/SessionAction.swift` — update clipboard fallback to construct `cd {project} && {resumeCmd}`
- [x] `Sources/SeshctlUI/SessionListViewModel.swift` — update `copyResumeCommand()` to construct compound form
- [x] `Tests/SeshctlUITests/SessionActionTests.swift` — update/replace the cd-stripping test
- [x] Run seshctl tests — 229/229 pass

## Acceptance Criteria
- [ ] [test] `recall --json bahia` returns `resume_cmd: "claude --resume <id>"` (no cd prefix)
- [ ] [test] `recall bahia` CLI display still shows `> cd /path && claude --resume <id>`
- [ ] [test] Pressing Enter on a recall result in seshctl GUI resumes the session correctly
- [ ] [test] Clipboard fallback contains the full compound command for manual pasting
