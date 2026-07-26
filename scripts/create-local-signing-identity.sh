#!/bin/bash
# Create a per-user, self-signed code-signing identity for stable local rebuilds.
set -euo pipefail

CERT_NAME="${SHOTPILL_SIGNING_IDENTITY:-Shot Pill Local Signing}"
LOGIN_KEYCHAIN="${SHOTPILL_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  echo "Signing identity already exists: $CERT_NAME"
  exit 0
fi

for tool in openssl security; do
  command -v "$tool" >/dev/null || { echo "ERROR: '$tool' is required." >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/shot-pill-cert.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASSWORD="$(openssl rand -hex 18)"

openssl req -new -newkey rsa:2048 -x509 -sha256 -nodes -days 3650 \
  -subj "/CN=$CERT_NAME/O=Shot Pill Local Development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$WORK/key.pem" \
  -out "$WORK/cert.pem"

openssl pkcs12 -export \
  -inkey "$WORK/key.pem" \
  -in "$WORK/cert.pem" \
  -name "$CERT_NAME" \
  -passout "pass:$PASSWORD" \
  -out "$WORK/identity.p12"

security import "$WORK/identity.p12" \
  -k "$LOGIN_KEYCHAIN" \
  -P "$PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

if ! security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  echo "ERROR: the identity was imported but is not available to codesign." >&2
  exit 1
fi

echo "Created local signing identity: $CERT_NAME"
echo "macOS may ask once for Keychain permission when the first build is signed."
