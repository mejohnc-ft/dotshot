#!/bin/bash
# Build dotshot.app from source. The app and bundled helpers are signed with one identity.
#
#   ./scripts/build.sh                      build ~/Applications/dotshot.app and launch it
#   ./scripts/build.sh --no-launch          build only
#   ./scripts/build.sh --adhoc              ad-hoc signature (CI, quick checks)
#   ./scripts/build.sh --universal          arm64 + x86_64 (release builds)
#   ./scripts/build.sh --app <path>         choose the output bundle path
#
# Signing identity: $DOTSHOT_SIGNING_IDENTITY, else "dotshot Local Signing" when present, else ad-hoc.
# A "Developer ID Application" identity enables the hardened runtime and a secure timestamp.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${DOTSHOT_APP_PATH:-$HOME/Applications/dotshot.app}"
BUNDLE_ID="com.mejohnc.dotshot"
MIN_MACOS="14.0"
SIGNING_IDENTITY="${DOTSHOT_SIGNING_IDENTITY:-dotshot Local Signing}"
LAUNCH=1
FORCE_ADHOC=0
UNIVERSAL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || { echo "--app requires a path" >&2; exit 2; }
      APP="$2"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --adhoc) FORCE_ADHOC=1; shift ;;
    --universal) UNIVERSAL=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

for tool in swiftc codesign iconutil lipo; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: '$tool' is required. Install Apple's Command Line Tools with: xcode-select --install" >&2
    exit 1
  }
done

if [ "$UNIVERSAL" -eq 1 ]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-build.XXXXXX")"
trap 'rm -rf "$BUILD_TMP"' EXIT

# compile <output> <sources...>: one slice per architecture, merged with lipo.
compile() {
  local output="$1"; shift
  local slices=() arch
  for arch in "${ARCHS[@]}"; do
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" "$@" -o "$BUILD_TMP/$(basename "$output").$arch"
    slices+=("$BUILD_TMP/$(basename "$output").$arch")
  done
  lipo -create "${slices[@]}" -output "$output"
}

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
install -m 644 "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

compile "$MACOS/dotshot" "$ROOT"/Sources/dotshot/*.swift
compile "$RESOURCES/panel" "$ROOT/Sources/helpers/panel.swift"
compile "$RESOURCES/ocr-slug" "$ROOT/Sources/helpers/ocr-slug.swift"
compile "$RESOURCES/avresize" "$ROOT/Sources/helpers/avresize.swift"
compile "$RESOURCES/trim" "$ROOT/Sources/helpers/trim.swift"
install -m 755 "$ROOT/scripts/dotshot-capture.sh" "$RESOURCES/dotshot-capture.sh"

swiftc -O "$ROOT/scripts/make-icon.swift" -o "$BUILD_TMP/make-icon"
"$BUILD_TMP/make-icon" "$BUILD_TMP/AppIcon.iconset"
iconutil -c icns "$BUILD_TMP/AppIcon.iconset" -o "$RESOURCES/AppIcon.icns"

if [ "$FORCE_ADHOC" -eq 1 ]; then
  SIGN="-"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\""; then
  SIGN="$SIGNING_IDENTITY"
elif [ -n "${DOTSHOT_SIGNING_IDENTITY:-}" ]; then
  echo "ERROR: signing identity '$SIGNING_IDENTITY' was not found." >&2
  exit 1
else
  SIGN="-"
  echo "WARNING: signing identity '$SIGNING_IDENTITY' was not found; using ad-hoc signing." >&2
  echo "         Screen Recording approval may need to be granted again after rebuilding." >&2
fi

SIGN_FLAGS=(--force --sign "$SIGN")
case "$SIGN" in
  "Developer ID Application"*) SIGN_FLAGS+=(--options runtime --timestamp) ;;
esac

# Sign inside-out: helpers first, then the bundle.
for helper in panel ocr-slug avresize trim; do
  codesign "${SIGN_FLAGS[@]}" --identifier "$BUNDLE_ID.$helper" "$RESOURCES/$helper"
done
codesign "${SIGN_FLAGS[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built and signed ($([ "$SIGN" = "-" ] && echo ad-hoc || echo "$SIGN"); ${ARCHS[*]}): $APP"
if [ "$LAUNCH" -eq 1 ]; then
  pkill -f "$APP/Contents/MacOS/dotshot" 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "Launched dotshot."
fi
