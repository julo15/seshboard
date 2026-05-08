# Code signing (Phase 1A: self-signed)

## Why

Seshctl uses AppleScript to focus terminal and browser tabs. macOS's TCC subsystem caches each "app A may control app B" Automation grant **per code signature**. If Seshctl's signature changes between rebuilds, every grant is forgotten and the user is re-prompted.

The fix is a stable code-signing identity. Phase 1A uses a **self-signed** cert kept in your login keychain so every `make sign` produces a bundle with the same signature → TCC remembers grants across rebuilds, restarts, and reinstalls.

For the bigger picture (why self-signed first, what Phase 1B / 2 / 3 add later), see the plan: [`.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md`](../.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md).

## First-time setup (once per Mac)

```bash
bash scripts/generate-self-signed-cert.sh
# or:
make cert-setup
```

This script is idempotent. On a fresh machine it:

1. Generates a 2048-bit RSA key + self-signed X.509 cert with `extendedKeyUsage = codeSigning` and `basicConstraints = CA:false`. 10-year validity.
2. Imports the keypair into your login keychain as the identity **`Seshctl Self-Signed`**, granting `/usr/bin/codesign` access to the private key.
3. Calls `security set-key-partition-list` so codesign can use the key without a UI prompt every time. **Note:** this step requires the login-keychain password and may print a warning + skip silently if it can't authenticate non-interactively. If it skipped, the **first** `make sign` after cert generation will pop a dialog: *"codesign wants to sign using key 'Seshctl Self-Signed' in your keychain."* Click **Always Allow** (not just *Allow*) so the ACL is updated and you don't see the dialog again. If you only clicked *Allow* by accident, re-run `make sign` and pick *Always Allow* the second time.
4. Writes the public-cert PEM to `Resources/seshctl-self-signed-public.pem` (committed to the repo so anyone can verify which cert was used).
5. Writes the full `.p12` (private + public) to `~/Library/Application Support/Seshctl/seshctl-self-signed.p12` — **NOT committed**.

If the identity already exists, the script no-ops and prints the SHA-1 thumbprint.

> **Back up the `.p12`.** If you lose it, you cannot reproduce the same code signature on a new Mac, so TCC grants on machines that already trust this build will not transfer. Drop a copy in 1Password (or your password manager of choice) right after running the script.

## Where things live

| Artifact | Path | Committed? |
|---|---|---|
| Login-keychain identity | `Seshctl Self-Signed` (private key + cert) | n/a |
| Backup `.p12` (private key) | `~/Library/Application Support/Seshctl/seshctl-self-signed.p12` | No |
| Public cert PEM | `Resources/seshctl-self-signed-public.pem` | Yes |

## Verifying the cert

```bash
# In the keychain — output line includes the SHA-1 thumbprint:
security find-identity -p codesigning | grep "Seshctl Self-Signed"

# In the committed PEM — same thumbprint:
openssl x509 -in Resources/seshctl-self-signed-public.pem -noout -fingerprint -sha1
```

Both fingerprints should match. If they don't, your local keychain has a different cert from what's committed — either re-run `scripts/generate-self-signed-cert.sh` after deleting the keychain identity, or restore from your `.p12` backup.

> **`-v` will report 0 valid identities — that's expected.** `security find-identity -v` filters to identities chaining to a trusted root, which a self-signed cert never does. The keychain reports the cert as `CSSMERR_TP_NOT_TRUSTED` to the trust validator. `codesign --sign "Seshctl Self-Signed"` ignores trust-validator state and just uses the matching private key, so signing works fine. The scripts in this repo intentionally call `find-identity` without `-v` for this reason.

## What `make sign` does

```bash
make bundle    # produces dist/Seshctl.app (unsigned)
make sign      # signs nested CLI, then outer .app
```

Under the hood, `scripts/sign-app.sh`:

1. Confirms the `Seshctl Self-Signed` identity is in the keychain.
2. Confirms `dist/Seshctl.app/Contents/MacOS/{SeshctlApp,seshctl-cli}` exist.
3. **Signs `seshctl-cli` first** (innermost binary) with `Resources/SeshctlCLI.entitlements` (empty entitlements — the CLI doesn't need Automation), `--options runtime` (hardened runtime), `--timestamp=none`, `--force`.
4. **Signs the outer `.app`** with `Resources/Seshctl.entitlements` (which grants `com.apple.security.automation.apple-events`), same flags.
5. Verifies with `codesign --verify --deep --strict --verbose=2`.
6. Prints the identity readout via `codesign -dv --verbose=4`.

> **No `--deep`.** `--deep` would re-sign the CLI without its CLI-specific entitlements, which would either over-grant entitlements to the CLI or strip the outer `.app`'s Automation entitlement. We sign explicitly in the right order instead.

> **`--timestamp=none`.** Apple's secure timestamping authority only signs Apple-issued certs. Phase 1B switches this to plain `--timestamp` once we have a Developer ID.

To sign with a non-default identity (Phase 1B):

```bash
bash scripts/sign-app.sh --identity "Developer ID Application: Julian Lo (TEAMID)"
```

## TCC persistence

macOS keys Automation grants by code signature. As long as the same cert signs every build, TCC keeps the grant. Verify this manually:

1. `make bundle && make sign && open dist/Seshctl.app`
2. Trigger a Seshctl action that drives Chrome (or any browser/terminal) via AppleScript. Click **Allow** when macOS prompts "Seshctl wants to control Chrome."
3. Quit Seshctl. Re-run `make bundle && make sign` to produce a fresh build with the same cert.
4. `open dist/Seshctl.app` again. Trigger the same action. **No prompt should appear** — TCC has cached the grant against this code signature.
5. Optionally restart your Mac and repeat step 4 to confirm the grant survives reboot.

If you ever do see a re-prompt where you didn't expect one, the most likely cause is that the cert identity changed (re-generated keypair). Same subject + same private key → same SHA-1 → same TCC grants. New keypair → new SHA-1 → grants invalidated.

## Cert expiry & renewal

The cert is valid for 10 years from generation. To renew or replace:

- **Same private key (preserves TCC):** export the existing key from the keychain, regenerate a cert with the same key, re-import. Documenting that flow is TBD; in practice, renew before expiry by re-running `scripts/generate-self-signed-cert.sh` after removing the existing keychain identity, then signal users that TCC grants need to be re-granted once.
- **Clean slate (loses TCC):** delete the `Seshctl Self-Signed` identity from Keychain Access, then re-run `scripts/generate-self-signed-cert.sh`. All Automation grants on every machine will need to be re-approved.

## Multiple Macs

Each machine runs its own `scripts/generate-self-signed-cert.sh` and gets its own keypair, so the SHA-1 thumbprint differs across machines. TCC grants are per-machine anyway, so this is fine for Phase 1.

If you want one stable identity across all your Macs, import the `.p12` backup on each machine (`security import ... -k login.keychain-db -P "" -T /usr/bin/codesign`) instead of running the generator script.

## Future: Phase 1B (Developer ID + notarization)

Once we enroll in the Apple Developer Program ($99/yr):

1. Generate a "Developer ID Application" cert in the Apple Developer portal; import it to the login keychain.
2. Sign with `bash scripts/sign-app.sh --identity "Developer ID Application: <Name> (<Team ID>)"`.
3. Drop `--timestamp=none` from the codesign call (use plain `--timestamp` to hit Apple's TSA).
4. Add `xcrun notarytool submit` + `xcrun stapler staple` to `make dist`.
5. Update README to remove the "right-click → Open" Gatekeeper note.

Switching from Phase 1A to 1B changes the signing identity, which **invalidates all existing TCC grants** — every user will be re-prompted once per browser/terminal. Communicate this clearly in the 1A→1B release notes. The full Phase 1B plan is in [`.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md`](../.agents/plans/2026-05-08-1151-seshctl-real-app-phase1.md) under "Future Phases".
