#!/bin/bash
# One-time Developer ID setup for release builds: installs the certificate, stores notarization
# credentials, and optionally adds the GitHub Actions secrets the release workflow uses.
#
#   ./scripts/setup-signing.sh --cer ~/Downloads/developerID_application.cer --key ~/.dotshot-signing/devid.key \
#       --p8 ~/Downloads/AuthKey_ABC123.p8 --key-id ABC123 --issuer 00000000-0000-0000-0000-000000000000 [--github]
#
# --key is the private key the certificate signing request was made from.
# Writes a password-protected .p12 next to the key (needed for --github; keep it private).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="dotshot-notary"
CER="" KEY="" P8="" KEY_ID="" ISSUER="" GITHUB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --cer) CER="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --p8) P8="$2"; shift 2 ;;
    --key-id) KEY_ID="$2"; shift 2 ;;
    --issuer) ISSUER="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --github) GITHUB=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
for pair in "cer:$CER" "key:$KEY" "p8:$P8" "key-id:$KEY_ID" "issuer:$ISSUER"; do
  [ -n "${pair#*:}" ] || { echo "missing --${pair%%:*} (see the usage at the top of this script)" >&2; exit 2; }
done
for file in "$CER" "$KEY" "$P8"; do [ -f "$file" ] || { echo "not found: $file" >&2; exit 1; }; done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "==> certificate"
openssl x509 -inform DER -in "$CER" -out "$WORK/cert.pem" 2>/dev/null || cp "$CER" "$WORK/cert.pem"
subject="$(openssl x509 -in "$WORK/cert.pem" -noout -subject)"
case "$subject" in
  *"Developer ID Application"*) ;;
  *) echo "This is not a Developer ID Application certificate: $subject" >&2; exit 1 ;;
esac
[ "$(openssl x509 -in "$WORK/cert.pem" -noout -pubkey | openssl sha256)" = "$(openssl pkey -in "$KEY" -pubout | openssl sha256)" ] \
  || { echo "The certificate does not match $KEY. Was the CSR made from a different key?" >&2; exit 1; }
echo "    $subject"

# The Developer ID intermediate must be present for the identity to count as valid.
if ! security find-certificate -c "Developer ID Certification Authority" >/dev/null 2>&1; then
  echo "==> Apple Developer ID intermediate certificate"
  curl -fsSL https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$WORK/DeveloperIDG2CA.cer"
  security import "$WORK/DeveloperIDG2CA.cer" -k "$KEYCHAIN" >/dev/null
fi

echo "==> .p12 and keychain"
P12="$(dirname "$KEY")/DeveloperID.p12"
P12_PASSWORD_FILE="$(dirname "$KEY")/DeveloperID.p12.password"
[ -s "$P12_PASSWORD_FILE" ] || { openssl rand -hex 24 > "$P12_PASSWORD_FILE"; chmod 600 "$P12_PASSWORD_FILE"; }
P12_PASSWORD="$(cat "$P12_PASSWORD_FILE")"
# SHA1/3DES keeps the .p12 importable by macOS `security`, which rejects OpenSSL 3 defaults.
openssl pkcs12 -export -inkey "$KEY" -in "$WORK/cert.pem" -name "dotshot Developer ID" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$P12_PASSWORD" -out "$P12"
chmod 600 "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1 \
  || echo "    (already in the keychain)"
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
[ -n "$IDENTITY" ] || { echo "No valid Developer ID Application identity after import." >&2; security find-identity -v -p codesigning; exit 1; }
echo "    identity: $IDENTITY"

echo "==> notarization credentials (keychain profile '$PROFILE')"
xcrun notarytool store-credentials "$PROFILE" --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null && echo "    verified with Apple"

if [ "$GITHUB" = 1 ]; then
  echo "==> GitHub Actions secrets"
  repo="$(cd "$ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner)"
  base64 -i "$P12" | gh secret set DEVELOPER_ID_P12_BASE64 -R "$repo"
  printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$repo"
  printf '%s' "$IDENTITY" | gh secret set DEVELOPER_ID_IDENTITY -R "$repo"
  gh secret set NOTARY_API_KEY_P8 -R "$repo" < "$P8"
  printf '%s' "$KEY_ID" | gh secret set NOTARY_API_KEY_ID -R "$repo"
  printf '%s' "$ISSUER" | gh secret set NOTARY_API_ISSUER -R "$repo"
  echo "    6 secrets set on $repo"
fi

cat <<EOF

Ready. Build a signed, notarized release with:

  DOTSHOT_SIGNING_IDENTITY="$IDENTITY" \\
  DOTSHOT_NOTARY_PROFILE=$PROFILE \\
  DOTSHOT_REQUIRE_NOTARIZATION=1 \\
  ./scripts/release.sh
EOF
