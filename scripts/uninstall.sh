#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Shot Pill.app"
CONFIG="$HOME/Library/Application Support/Shot Pill"
SHOTS="$HOME/Shots"

echo "This removes Shot Pill.app and unregisters Launch at Login."
echo "It keeps your configuration and captures by default:"
echo "  $CONFIG"
echo "  $SHOTS"
printf "Continue? [y/N] "
read -r answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) exit 0 ;;
esac

if [ -d "$APP" ]; then
  open -b com.johnc.shotpill 'shotpill://settings' >/dev/null 2>&1 || true
  running_pid="$(pgrep -f "$APP/Contents/MacOS/Shot Pill" | head -1 || true)"
  [ -z "$running_pid" ] || kill "$running_pid" 2>/dev/null || true
  mv "$APP" "$HOME/.Trash/Shot Pill.app"
  echo "Moved Shot Pill.app to Trash."
fi

echo "To remove settings later: rm -r '$CONFIG'"
echo "To remove captures later: rm -r '$SHOTS'"
