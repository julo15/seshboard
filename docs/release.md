# Cutting a release (Phase 1, manual)

This walks through producing a signed `.dmg` and uploading it to a GitHub Release. Phase 1 is intentionally manual — `make dist` on your Mac, `gh release create` to publish, Slack a link to users. CI automation is deferred to Phase 3.

For the bigger picture (why we're self-signed first, what later phases add), see the plan: [`.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md`](../.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md).

## Prerequisites (one-time)

Install the tools:

```bash
brew install create-dmg gh jq
```

- [`create-dmg`](https://github.com/create-dmg/create-dmg) — builds the styled `.dmg`.
- [`gh`](https://cli.github.com/) — GitHub CLI used to create the Release. Auth via `gh auth login`.
- `jq` — used by hook installer scripts; required for end-to-end smoke tests.

Set up the self-signed code-signing identity (once per Mac):

```bash
make cert-setup
```

See [`docs/signing.md`](signing.md) for what this does, where the cert lives, and how to back it up. **Back up the `.p12`** to 1Password before continuing — losing it means a different code signature on the next Mac, which invalidates every TCC grant.

Authenticate the GitHub CLI (once per Mac):

```bash
gh auth login
```

See the [`gh` docs](https://cli.github.com/manual/gh_auth_login) for OAuth vs. token flow.

## Pre-release checklist

Before tagging anything:

- [ ] **Tests pass.** Run `swift test` in a subagent (per [`AGENTS.md`](../AGENTS.md)). Don't proceed on red.
- [ ] **Bump `CFBundleShortVersionString`** in [`Resources/Info.plist`](../Resources/Info.plist). E.g. `0.1.0` → `0.1.1`. This is the human-facing version.
- [ ] **Bump `CFBundleVersion`** to a new monotonically increasing integer. E.g. `1` → `2`. This is the machine-facing version Sparkle (Phase 2) will eventually compare. Note: `CFBundleVersion` is a string-typed plist value (`<string>` in `Resources/Info.plist`) containing a monotonically-increasing integer.
- [ ] **Update `CHANGELOG.md`** with release notes. The repo doesn't have a `CHANGELOG.md` yet — recommend creating one alongside the first DMG release. Use whatever convention you like ([Keep a Changelog](https://keepachangelog.com/) is a fine default).
- [ ] Working tree is clean: `git status` shows nothing uncommitted.

## Build & sign

```bash
make dist
```

This runs three steps in order:

1. `make bundle` — universal release build, assembles `dist/Seshctl.app`.
2. `make sign` — signs `seshctl-cli` (nested) then `Seshctl.app` (outer) with the `Seshctl Self-Signed` identity. Hardened runtime + `--timestamp=none`.
3. `make-dmg` — produces `dist/Seshctl-<VERSION>.dmg` via `create-dmg`.

Output: `dist/Seshctl-<VERSION>.dmg` ready to attach to a Release.

## Smoke test the DMG locally

Don't skip this. The `.dmg` is what users run, not the `.app` you just built.

```bash
open dist/Seshctl-<VERSION>.dmg
```

In Finder:

1. Drag `Seshctl.app` to a temp folder (e.g. `~/Desktop/seshctl-smoke/`). **Do NOT drag to `/Applications`** — that's the manual end-to-end test in Step 7 of the Phase 1 plan.
2. Right-click the copied `Seshctl.app` → **Open**. Click **Open** again on the Gatekeeper warning. (Self-signed cert; this is expected until Phase 1B notarization.)
3. The welcome panel should appear (the dragged-to-temp install has no marker file at `~/Library/Application Support/Seshctl/installed-v1.json`, so `FirstLaunchInstaller` triggers).
4. **Cancel out without installing** — you don't want this temp build to overwrite your dev hooks/symlinks.
5. Quit Seshctl from the temp folder.

Detach the DMG:

```bash
hdiutil detach "/Volumes/Seshctl <VERSION>"
```

## Cut the release

Tag and publish in one shot:

```bash
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)
gh release create "v${VERSION}" \
  "dist/Seshctl-${VERSION}.dmg" \
  --title "Seshctl ${VERSION}" \
  --notes-file CHANGELOG.md
```

Adjust `--notes-file` to whatever your CHANGELOG conventions are. If you keep release notes inline (without a `CHANGELOG.md`), swap `--notes-file CHANGELOG.md` for `--notes "..."` or `--notes-from-tag`.

This will:
- Create the `v${VERSION}` git tag locally (if not present) and push it.
- Create the GitHub Release with the DMG attached.
- Print the Release URL.

> **Stage 1A note:** include in the release notes that on first install users must **right-click → Open** to bypass Gatekeeper. This will go away in Phase 1B once we notarize. See [Troubleshooting](#troubleshooting) below.

## Distribute

Get the Release URL:

```bash
gh release view "v${VERSION}" --json url -q .url
```

Slack the link to anyone running Seshctl. Include in the message:

- "Drag to /Applications, replace if it's already there. TCC grants are preserved across replacements."
- "First install: right-click → Open to bypass Gatekeeper (self-signed cert; will go away in 1B)."
- A one-line "what changed" summary.

## After-release sanity check

The point of this step is to verify the release reproduces the user experience, not just yours.

- Download the DMG from the GitHub Release URL on a *different* Mac (or, if you only have one Mac, temporarily move `Seshctl Self-Signed` out of your login keychain — the code signature stays embedded but trust validation runs against a clean keychain).
- Drag to `/Applications`, right-click → Open.
- Confirm the welcome panel appears, click Install, confirm the symlink + hooks land.
- Trigger a remote Claude session focus, allow the Automation TCC prompt, and confirm focusing again does NOT re-prompt.

## Troubleshooting

### `create-dmg` failed with `hdiutil: create failed`

This usually means a stale `swift-build` / `swift-frontend` / `pkgbuild` process is holding a lock on something inside the bundle. Run:

```bash
make kill-build
make dist
```

If the second attempt also fails, there may be a leftover mounted DMG from a previous run — check with `mount | grep Seshctl` and detach it.

### `codesign` warns about timestamp

Expected with self-signed certs. We pass `--timestamp=none` because Apple's secure timestamping authority only signs Apple-issued certs. This warning will disappear in Phase 1B once we have a Developer ID and use plain `--timestamp`. Details in [`docs/signing.md`](signing.md).

### Sparkle / appcast — where's the auto-update?

Deferred to **Phase 2** of the plan: [`.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md`](../.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md) under "Future Phases → Phase 2". For now, releases are manual: Slack the link, users download the new DMG.

### macOS Gatekeeper says the app is "damaged or untrusted" / "cannot verify developer"

This is the normal Stage 1A experience. The fix until Phase 1B notarization ships:

1. Right-click `Seshctl.app` in Finder.
2. Click **Open** (not double-click).
3. Click **Open** in the dialog that says "macOS cannot verify the developer."

This stores a per-user override; subsequent launches work via double-click. Document this clearly in the release notes for every Stage 1A release. Phase 1B will replace this with a notarized signature, and the release notes for the 1A→1B version should call out the one-time TCC re-prompt that comes with the cert change.

If you see "damaged" *after* a successful first-run with right-click → Open, the bundle was probably modified after signing (e.g. xattr from the download). Try `xattr -cr /Applications/Seshctl.app` to strip quarantine, then right-click → Open again.
