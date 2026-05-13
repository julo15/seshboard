#!/usr/bin/env bash
# Generate (or reuse) a self-signed code-signing identity named
# "Seshctl Self-Signed" in the user's login keychain.
#
# Idempotent: if the identity already exists, prints the SHA-1 thumbprint and
# exits 0 without regenerating anything.
#
# Outputs:
#   - Login keychain: imported "Seshctl Self-Signed" identity (private + public)
#   - Resources/seshctl-self-signed-public.pem  (committed; public cert only)
#   - ~/Library/Application Support/Seshctl/seshctl-self-signed.p12  (NOT committed)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

IDENTITY_NAME="Seshctl Self-Signed"
PUBLIC_PEM="${REPO_DIR}/Resources/seshctl-self-signed-public.pem"
BACKUP_DIR="${HOME}/Library/Application Support/Seshctl"
BACKUP_P12="${BACKUP_DIR}/seshctl-self-signed.p12"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# macOS `security import` rejects empty PKCS#12 passwords ("MAC verification
# failed"). We use a fixed, non-secret password — the .p12 just needs to be
# unwrappable. The private key inside is still protected by the login
# keychain's ACL.
P12_PASSWORD="seshctl"

# Prefer macOS's bundled LibreSSL — its PKCS#12 output is consistently
# accepted by macOS `security`. Homebrew OpenSSL 3.x produces files that
# `security` rejects with MAC verification errors.
OPENSSL="${OPENSSL:-/usr/bin/openssl}"

print_thumbprint() {
  # Extract just the line for our identity. Format:
  #   1) <SHA1>  "Seshctl Self-Signed" [(CSSMERR_TP_NOT_TRUSTED)]
  #
  # Note: we use `security find-identity -p codesigning` WITHOUT `-v`. A
  # self-signed cert always shows up as `CSSMERR_TP_NOT_TRUSTED` to the
  # validator (no chain to a trusted root) but `codesign --sign "<name>"`
  # still uses it just fine — the validator's notion of "valid" is stricter
  # than what codesign requires.
  local line
  line="$(security find-identity -p codesigning | grep "${IDENTITY_NAME}" || true)"
  if [[ -n "${line}" ]]; then
    echo "${line}"
  else
    echo "(no thumbprint found)" >&2
  fi
}

# 1. If the identity already exists, no-op.
if security find-identity -p codesigning | grep -q "${IDENTITY_NAME}"; then
  echo "Already installed: $(print_thumbprint)"
  exit 0
fi

echo "Generating self-signed code-signing identity: ${IDENTITY_NAME}"

# 2. Set up a working directory we own and clean up at the end.
WORK_DIR="$(mktemp -d -t seshctl-cert.XXXXXX)"
cleanup() {
  rm -rf "${WORK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

KEY_FILE="${WORK_DIR}/seshctl.key"
CERT_FILE="${WORK_DIR}/seshctl.crt"
P12_FILE="${WORK_DIR}/seshctl.p12"
EXT_FILE="${WORK_DIR}/v3.cnf"

# 3. OpenSSL config. LibreSSL (the macOS-bundled openssl) requires `[req]`
#    and `distinguished_name` even when -subj is supplied. The v3 extensions
#    section is what actually matters for code signing: not a CA, signing-only
#    key usage, codeSigning EKU.
cat > "${EXT_FILE}" <<'EOF'
[ req ]
distinguished_name = req_dn
prompt = no

[ req_dn ]
CN = Seshctl Self-Signed
O = Seshctl
C = US

[ v3_codesign ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 4. Generate key + self-signed cert (10-year validity, 2048-bit RSA, no DES password).
"${OPENSSL}" req -x509 \
  -newkey rsa:2048 \
  -nodes \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -days 3650 \
  -subj "/CN=${IDENTITY_NAME}/O=Seshctl/C=US" \
  -extensions v3_codesign \
  -config "${EXT_FILE}" \
  >/dev/null 2>&1

# 5. Bundle into a PKCS#12. The password is just a wrapper for the file format;
#    the key's real protection is the login-keychain ACL.
"${OPENSSL}" pkcs12 -export \
  -inkey "${KEY_FILE}" \
  -in "${CERT_FILE}" \
  -out "${P12_FILE}" \
  -name "${IDENTITY_NAME}" \
  -passout "pass:${P12_PASSWORD}"

# 6. Import into login keychain. -T /usr/bin/codesign grants codesign access
#    to the private key without a UI prompt every time.
security import "${P12_FILE}" \
  -k "${LOGIN_KEYCHAIN}" \
  -P "${P12_PASSWORD}" \
  -T /usr/bin/codesign

# 7. Allow apple-tool / apple / codesign to use the key without prompting.
#    Empty -k password works if the login keychain is currently unlocked. If
#    this fails, the user can re-run it manually after unlocking; we don't
#    hard-fail here because the import already succeeded.
if ! security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s -k "" \
      "${LOGIN_KEYCHAIN}" >/dev/null 2>&1; then
  echo "Warning: set-key-partition-list failed. You may be prompted by macOS the first time codesign uses this key." >&2
fi

# 8. Save the public-cert PEM into the repo (committed; not sensitive).
mkdir -p "$(dirname "${PUBLIC_PEM}")"
cp "${CERT_FILE}" "${PUBLIC_PEM}"

# 9. Save the .p12 backup outside the repo. Contains the PRIVATE key — DO NOT commit.
mkdir -p "${BACKUP_DIR}"
cp "${P12_FILE}" "${BACKUP_P12}"
chmod 600 "${BACKUP_P12}"

echo ""
echo "Done."
echo ""
echo "  Public cert (committed):  ${PUBLIC_PEM}"
echo "  Private .p12 backup:      ${BACKUP_P12}"
echo ""
echo "  Backup this file to 1Password if you want the same cert on other Macs:"
echo "    ${BACKUP_P12}"
echo ""
echo "Identity in keychain:"
print_thumbprint
