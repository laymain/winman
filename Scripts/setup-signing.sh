#!/bin/bash
# Creates a stable self-signed code-signing certificate in the login keychain
# and trusts it for the codeSigning policy.
#
# Why: ad-hoc signatures (codesign --sign -) change their code hash on every
# rebuild. macOS keys the Accessibility (TCC) grant to that hash, so every
# rebuild silently revokes Accessibility permission and the app stops working
# until you re-grant it. A stable certificate keeps the same identity across
# rebuilds, so you grant Accessibility once.
#
# Usage:  ./Scripts/setup-signing.sh

set -euo pipefail

cd "$(dirname "$0")/.."
WORKDIR=".signing"
IDENTITY="WindowManager Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
PASSWORD="localdev"   # local, non-extractable-use passphrase for the key file

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Checking for existing identity..."
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "    Already present: $IDENTITY"
    exit 0
fi

echo "==> Generating private key + self-signed certificate (codeSigning EKU)..."
openssl genrsa -out codesign.key 2048 2>/dev/null

cat > openssl.cnf <<EOF
[req]
distinguished_name = req_dn
prompt = no
[req_dn]
CN = $IDENTITY
O = Local Dev
[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -new -x509 -key codesign.key -out codesign.crt -days 3650 \
  -config openssl.cnf -extensions v3_req

echo "==> Bundling into PKCS#12 and importing into login keychain..."
# Note: security import requires -f pkcs12, and an empty password round-trip is
# unreliable, so we use a local passphrase.
openssl pkcs12 -export -out codesign.p12 -inkey codesign.key -in codesign.crt \
  -passout "pass:$PASSWORD" -name "$IDENTITY"
security import codesign.p12 -k "$KEYCHAIN" -f pkcs12 -P "$PASSWORD" \
  -T /usr/bin/codesign
rm -f codesign.p12

echo "==> Trusting the certificate for the codeSigning policy..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" codesign.crt

echo "==> Verifying:"
security find-identity -v -p codesigning

echo
echo "Done. Rebuild with ./Scripts/make-app.sh — the signature (and your"
echo "Accessibility permission) will now be stable across rebuilds."
