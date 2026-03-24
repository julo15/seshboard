# Git Repo Context Display

Show git repo name and branch in the session UI instead of just the directory name.

## Display rules

1. **Repo name** (from `git remote get-url origin`, or toplevel dirname if no remote)
2. **Directory name** — only if it differs from repo name
3. **Branch** — if in a git repo

| Scenario | Display |
|---|---|
| Normal clone, `main` | `seshctl · main` |
| Normal clone, feature branch | `seshctl · feat-auth` |
| Renamed clone, `main` | `seshctl · my-folder · main` |
| Renamed clone, feature branch | `seshctl · my-folder · feat-auth` |
| Worktree | `seshctl · .worktree-abc123 · feat-auth` |
| Local repo (no remote), `main` | `experiments · main` |
| Not a git repo | `random-dir` |

## Steps

- [x] 1. **Session model + migration**: Add `gitRepoName` and `gitBranch` fields to `Session`, add v5 migration
- [x] 2. **Git detection utility**: Create `GitContext` helper that runs git commands to resolve repo name + branch
- [x] 3. **CLI start**: Detect git context at session start, pass to database
- [x] 4. **Display name logic**: Add `Session.displayName` computed property implementing the resolution rules
- [x] 5. **UI updates**: Use `displayName` in `SessionRowView`, `SessionDetailView`, CLI `List`/`Show`, and search filtering
- [x] 6. **Hook updates**: N/A — git detection happens in CLI, no hook changes needed
- [x] 7. **Tests**: Display name logic tests (9), git context parsing tests (6), database tests (3)
