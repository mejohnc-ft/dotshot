#!/bin/bash
# Render the demo animation (docs/images/demo.gif, demo.mp4, demo-poster.png) from scripts/docs/demo.html.
# Run capture-media.sh first. Requires Google Chrome and ffmpeg.
#
#   ./scripts/docs/make-demo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW="$ROOT/build/media/raw"
WORK="$ROOT/build/media/demo"
IMAGES="$ROOT/docs/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FPS="${FPS:-12}"
DURATION="${DURATION:-11.5}"

[ -f "$RAW/pill-expanded.png" ] || { echo "Run scripts/docs/capture-media.sh first." >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)." >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/raw" "$WORK/frames" "$IMAGES"
cp "$RAW/pill-expanded.png" "$RAW/pill-collapsed.png" "$WORK/raw/"
cp "$ROOT/scripts/docs/demo.html" "$WORK/demo.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,800 \
  --screenshot="$WORK/raw/sample-settings.png" "file://$ROOT/scripts/docs/sample-shots.html#settings" >/dev/null 2>&1

# App icon from a fresh build's icon generator.
swiftc -O "$ROOT/scripts/make-icon.swift" -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/AppIcon.iconset"
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$WORK/raw/app-icon.png"

frames="$(awk -v d="$DURATION" -v f="$FPS" 'BEGIN { printf "%d", d * f }')"
echo "==> rendering $frames frames"
# Sequential on purpose: parallel headless Chrome instances stall on macOS.
for n in $(seq 0 $((frames - 1))); do
  t="$(awk -v n="$n" -v f="$FPS" 'BEGIN { printf "%.4f", n / f }')"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=960,540 \
    --screenshot="$WORK/frames/$(printf %04d "$n").png" "file://$WORK/demo.html#t=$t" >/dev/null 2>&1
done
[ "$(ls "$WORK/frames" | wc -l | tr -d ' ')" -eq "$frames" ] || { echo "missing frames" >&2; exit 1; }

echo "==> encoding"
ffmpeg -loglevel error -y -framerate "$FPS" -i "$WORK/frames/%04d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$IMAGES/demo.mp4"
ffmpeg -loglevel error -y -framerate "$FPS" -i "$WORK/frames/%04d.png" \
  -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 "$IMAGES/demo.gif"
cp "$WORK/frames/$(printf %04d $((FPS * 10)))".png "$WORK/poster-2x.png"
sips -Z 1280 "$WORK/poster-2x.png" --out "$IMAGES/demo-poster.png" >/dev/null

ls -lh "$IMAGES/demo.gif" "$IMAGES/demo.mp4" "$IMAGES/demo-poster.png" | awk '{ print "  " $NF "  " $5 }'

# The landing page serves its own copies.
mkdir -p "$ROOT/site/images"
cp "$IMAGES/demo.gif" "$IMAGES/demo.mp4" "$IMAGES/demo-poster.png" "$ROOT/site/images/"
