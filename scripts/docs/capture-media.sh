#!/bin/bash
# Regenerate documentation screenshots from a real, isolated dotshot build.
# Uses fake destinations and sample captures; never reads your dotshot settings.
# Requires Screen Recording permission for the terminal running this script and Google Chrome (sample images).
#
#   ./scripts/docs/capture-media.sh [output-dir]     default: build/media/raw
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/build/media/raw}"
WORK="$ROOT/build/media/work"
APP="$WORK/dotshot.app"
DEMO_ID="com.mejohnc.dotshot.demo"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$OUT" "$WORK/config" "$WORK/Shots"

echo "==> demo build"
"$ROOT/scripts/build.sh" --app "$APP" --no-launch --adhoc >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEMO_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier "$DEMO_ID" "$APP" 2>/dev/null
swiftc -O "$ROOT/scripts/docs/window-ids.swift" -o "$WORK/window-ids"

printf '# name\tssh-host-or-alias\tremote-folder\nwork\tdev@mac-studio.local\t/Users/dev/inbound\ngpu\tdev@gpu-box\t/home/dev/inbound\nnas\tadmin@nas\t/srv/inbound\nci\tbuild@ci-runner\t/home/build/inbound\n' \
  > "$WORK/config/destinations.tsv"
defaults delete "$DEMO_ID" >/dev/null 2>&1 || true
defaults write "$DEMO_ID" dotshot.onboardingComplete -bool true
defaults write "$DEMO_ID" dotshot.dest work

echo "==> sample captures"
rm -f "$WORK/Shots"/*.png
minute=10
for pair in chart:p95-latency-api-gateway login:sign-in-invalid-credentials tests:payment-form-test-failed settings:network-settings-proxy-host; do
  view="${pair%%:*}"; name="${pair#*:}-20260916-10${minute}00.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1280,800 \
    --screenshot="$WORK/Shots/$name" "file://$ROOT/scripts/docs/sample-shots.html#$view" >/dev/null 2>&1
  touch -t "2026091610$minute" "$WORK/Shots/$name"
  minute=$((minute + 1))
done

# shoot_once <output-name> <expected-window-min-width> [ENV=VALUE ...]: launch, capture the largest window, quit.
shoot_once() {
  local name="$1" min_width="$2"; shift 2
  local env_args=(--env DOTSHOT_CONFIG_DIR="$WORK/config" --env DOTSHOT_SHOTS_DIR="$WORK/Shots"
                  --env DOTSHOT_CAPTURABLE=1 --env DOTSHOT_NO_AUTO_SETUP=1)
  local pair
  for pair in "$@"; do env_args+=(--env "$pair"); done
  pkill -f "$APP/Contents/MacOS/dotshot" 2>/dev/null || true
  while pgrep -f "$APP/Contents/MacOS/dotshot" >/dev/null; do sleep 0.2; done
  open -n "${env_args[@]}" "$APP"
  local pid="" window=""
  for _ in $(seq 1 50); do
    sleep 0.3
    pid="$(pgrep -n -f "$APP/Contents/MacOS/dotshot" || true)"
    [ -n "$pid" ] || continue
    window="$("$WORK/window-ids" "$pid" | awk -v min="$min_width" '$2 >= min { print $1; exit }')"
    [ -n "$window" ] && break
  done
  [ -n "$window" ] || { echo "no window for $name" >&2; return 1; }
  sleep 1.5   # thumbnails, materials, and animations settle
  screencapture -x -o -l "$window" "$OUT/$name.png"
  echo "    $name.png"
}

# Launches occasionally race the previous instance's exit; retry a few times.
shoot() {
  local _
  for _ in 1 2 3; do
    shoot_once "$@" && return 0
    sleep 1
  done
  return 1
}

echo "==> app windows"
shoot pill-expanded 400 DOTSHOT_DEMO_STATE=expanded
shoot pill-collapsed 40 DOTSHOT_DEMO_STATE=collapsed
shoot pill-drop 300 DOTSHOT_DEMO_STATE=drop
shoot recording-picker 600 DOTSHOT_DEMO_STATE=collapsed DOTSHOT_DEMO_PICKER=1
for step in welcome permissions connect destinations test login appearance "done"; do
  shoot "setup-$step" 800 DOTSHOT_DEMO_STATE=collapsed DOTSHOT_DEMO_SETUP="$step"
done

# The intro video switches destinations, so it needs the pill pointed at another machine too.
defaults write "$DEMO_ID" dotshot.dest gpu
shoot pill-expanded-gpu 400 DOTSHOT_DEMO_STATE=expanded
defaults write "$DEMO_ID" dotshot.dest work
pkill -f "$APP/Contents/MacOS/dotshot" 2>/dev/null || true

echo "==> post-recording panel"
DOTSHOT_CAPTURABLE=1 "$APP/Contents/Resources/panel" "Recording ready" "Send as-is, trim in QuickTime, or resize smaller." 0 "Send,Trim,Resize" "$WORK/Shots" >/dev/null 2>&1 &
panel_pid=$!
window=""
for _ in $(seq 1 30); do
  sleep 0.3
  window="$("$WORK/window-ids" "$panel_pid" | awk '$2 >= 300 { print $1; exit }')"
  [ -n "$window" ] && break
done
sleep 1.5
if [ -n "$window" ]; then
  screencapture -x -o -l "$window" "$OUT/recording-ready.png" && echo "    recording-ready.png"
else
  echo "no window for recording-ready" >&2
fi
kill "$panel_pid" 2>/dev/null || true
wait "$panel_pid" 2>/dev/null || true

pkill -f "$APP/Contents/MacOS/dotshot" 2>/dev/null || true
defaults delete "$DEMO_ID" >/dev/null 2>&1 || true
echo "Raw captures: $OUT"
