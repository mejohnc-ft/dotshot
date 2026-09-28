#!/bin/bash
# Build release artifacts: a universal dotshot.app packaged as a DMG and a ZIP, plus checksums.
#
#   ./scripts/release.sh                  version from Resources/Info.plist
#
# Signing and notarization are used when configured, otherwise the build is ad-hoc signed:
#   DOTSHOT_SIGNING_IDENTITY   "Developer ID Application: Name (TEAMID)"
#   DOTSHOT_NOTARY_PROFILE     keychain profile from `xcrun notarytool store-credentials`
#   or DOTSHOT_NOTARY_KEY / DOTSHOT_NOTARY_KEY_ID / DOTSHOT_NOTARY_ISSUER   App Store Connect API key (CI)
#   DOTSHOT_REQUIRE_NOTARIZATION=1   fail instead of producing an unnotarized build
#   DOTSHOT_SKIP_TESTS=1             skip scripts/test.sh (the release workflow runs it in a separate job)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
OUT="$ROOT/build/release/$VERSION"
APP="$OUT/dotshot.app"
DMG="$OUT/dotshot-$VERSION.dmg"
ZIP="$OUT/dotshot-$VERSION.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

if [ "${DOTSHOT_SKIP_TESTS:-0}" = 1 ]; then
  echo "==> tests skipped (DOTSHOT_SKIP_TESTS=1; CI runs them in an earlier job)"
else
  echo "==> tests"
  "$ROOT/scripts/test.sh"
fi

echo "==> build $VERSION"
if [ -n "${DOTSHOT_SIGNING_IDENTITY:-}" ]; then
  DOTSHOT_SIGNING_IDENTITY="$DOTSHOT_SIGNING_IDENTITY" "$ROOT/scripts/build.sh" --universal --no-launch --app "$APP"
  SIGNED=1
else
  "$ROOT/scripts/build.sh" --universal --no-launch --adhoc --app "$APP"
  SIGNED=0
fi

notary_args=()
if [ -n "${DOTSHOT_NOTARY_PROFILE:-}" ]; then
  notary_args=(--keychain-profile "$DOTSHOT_NOTARY_PROFILE")
elif [ -n "${DOTSHOT_NOTARY_KEY:-}" ]; then
  notary_args=(--key "$DOTSHOT_NOTARY_KEY" --key-id "$DOTSHOT_NOTARY_KEY_ID" --issuer "$DOTSHOT_NOTARY_ISSUER")
fi
NOTARIZE=0
if [ "$SIGNED" -eq 1 ] && [ "${#notary_args[@]}" -gt 0 ]; then
  NOTARIZE=1
elif [ "${DOTSHOT_REQUIRE_NOTARIZATION:-0}" = 1 ]; then
  echo "ERROR: notarization requires DOTSHOT_SIGNING_IDENTITY and notary credentials." >&2
  exit 1
fi

notarize() {
  echo "==> notarize $(basename "$1")"
  xcrun notarytool submit "$1" "${notary_args[@]}" --wait --timeout 30m
  xcrun stapler staple "$2"
}

if [ "$NOTARIZE" -eq 1 ]; then
  ditto -c -k --keepParent "$APP" "$OUT/notarize-app.zip"
  notarize "$OUT/notarize-app.zip" "$APP"
  rm -f "$OUT/notarize-app.zip"
fi

echo "==> zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/dotshot.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "dotshot $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
if [ "$SIGNED" -eq 1 ]; then
  codesign --force --sign "$DOTSHOT_SIGNING_IDENTITY" --timestamp "$DMG"
fi
if [ "$NOTARIZE" -eq 1 ]; then
  notarize "$DMG" "$DMG"
fi

echo "==> verify"
codesign --verify --deep --strict "$APP"
hdiutil verify -quiet "$DMG"
if [ "$NOTARIZE" -eq 1 ]; then
  spctl --assess --type execute --verbose "$APP"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
DMG_SHA="$(awk -v f="$(basename "$DMG")" '$2 == f { print $1 }' "$OUT/SHA256SUMS.txt")"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$DMG_SHA/g" "$ROOT/packaging/homebrew/dotshot.rb.in" > "$OUT/dotshot.rb"

STATUS="ad-hoc signed (not notarized)"
[ "$SIGNED" -eq 1 ] && STATUS="Developer ID signed (not notarized)"
[ "$NOTARIZE" -eq 1 ] && STATUS="Developer ID signed and notarized"
printf '%s\n' "$STATUS" > "$OUT/SIGNING.txt"

echo
echo "dotshot $VERSION — $STATUS"
ls -lh "$OUT" | awk 'NR > 1 { print "  " $NF "  " $5 }'
