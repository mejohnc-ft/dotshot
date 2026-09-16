#!/bin/bash
# Remove dotshot.app (or the legacy Shot Pill.app with --legacy). Settings and captures are kept.
set -euo pipefail

NAME="dotshot"
BUNDLE_ID="com.mejohnc.dotshot"
CONFIG="$HOME/Library/Application Support/dotshot"
if [ "${1:-}" = "--legacy" ]; then
  NAME="Shot Pill"
  BUNDLE_ID="com.johnc.shotpill"
  CONFIG="$HOME/Library/Application Support/Shot Pill"
fi
SHOTS="$HOME/Shots"

APPS=()
for candidate in "$HOME/Applications/$NAME.app" "/Applications/$NAME.app"; do
  [ -d "$candidate" ] && APPS+=("$candidate")
done

echo "This quits $NAME and moves it to the Trash:"
if [ "${#APPS[@]}" -eq 0 ]; then echo "  (no $NAME.app found)"; else printf '  %s\n' "${APPS[@]}"; fi
echo "It keeps your settings and captures:"
echo "  $CONFIG"
echo "  $SHOTS"
printf "Continue? [y/N] "
read -r answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) exit 0 ;;
esac

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 0.5
for app in "${APPS[@]+"${APPS[@]}"}"; do
  pkill -f "$app/Contents/MacOS/" 2>/dev/null || true
  osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' "$app" >/dev/null 2>&1 \
    || mv "$app" "$HOME/.Trash/$(basename "$app" .app)-$(date +%s).app"
  echo "Moved $app to the Trash."
done

echo
echo "macOS removes the Login Item automatically once the app is gone."
echo "To also remove settings:    rm -r '$CONFIG' && defaults delete $BUNDLE_ID"
echo "To also remove captures:    rm -r '$SHOTS'"
echo "To reset Screen Recording:  tccutil reset ScreenCapture $BUNDLE_ID"
