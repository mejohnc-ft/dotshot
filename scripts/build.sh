#!/bin/bash
# Build Shot Pill.app from source. The app and bundled helpers are signed with one identity.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${SHOTPILL_APP_PATH:-$HOME/Applications/Shot Pill.app}"
BUNDLE_ID="com.johnc.shotpill"
SIGNING_IDENTITY="${SHOTPILL_SIGNING_IDENTITY:-Shot Pill Local Signing}"
LAUNCH=1
FORCE_ADHOC=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || { echo "--app requires a path" >&2; exit 2; }
      APP="$2"; shift 2 ;;
    --no-launch)
      LAUNCH=0; shift ;;
    --adhoc)
      FORCE_ADHOC=1; shift ;;
    *)
      echo "unknown option: $1" >&2
      exit 2 ;;
  esac
done

for tool in swiftc codesign iconutil; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: '$tool' is required. Install Apple's Command Line Tools with: xcode-select --install" >&2
    exit 1
  }
done

CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/shot-pill-build.XXXXXX")"
trap 'rm -rf "$BUILD_TMP"' EXIT

mkdir -p "$MACOS" "$RESOURCES"
install -m 644 "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

swiftc -O "$ROOT/Sources/ShotPill.swift" -o "$MACOS/Shot Pill"
swiftc -O "$ROOT/Sources/Panel.swift" -o "$RESOURCES/panel"
swiftc -O "$ROOT/Sources/OCRSlug.swift" -o "$RESOURCES/ocr-slug"
swiftc -O "$ROOT/Sources/AVResize.swift" -o "$RESOURCES/avresize"
install -m 755 "$ROOT/scripts/shot-to-work.sh" "$RESOURCES/shot-to-work.sh"

swiftc -O "$ROOT/scripts/make-icon.swift" -o "$BUILD_TMP/make-icon"
"$BUILD_TMP/make-icon" "$BUILD_TMP/AppIcon.iconset"
iconutil -c icns "$BUILD_TMP/AppIcon.iconset" -o "$RESOURCES/AppIcon.icns"

if [ "$FORCE_ADHOC" -eq 1 ]; then
  SIGN="-"
elif security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\""; then
  SIGN="$SIGNING_IDENTITY"
else
  SIGN="-"
  echo "WARNING: signing identity '$SIGNING_IDENTITY' was not found; using ad-hoc signing." >&2
  echo "         Screen Recording approval may need to be granted again after rebuilding." >&2
fi

for helper in "$RESOURCES/panel" "$RESOURCES/ocr-slug" "$RESOURCES/avresize"; do
  codesign --force --sign "$SIGN" "$helper"
done
codesign --force --deep --sign "$SIGN" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built and signed: $APP"
if [ "$LAUNCH" -eq 1 ]; then
  running_pid="$(pgrep -f "$APP/Contents/MacOS/Shot Pill" | head -1 || true)"
  [ -z "$running_pid" ] || kill "$running_pid" 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "Launched Shot Pill."
fi
