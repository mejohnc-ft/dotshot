#!/bin/bash
# Render the intro video (docs/images/intro.mp4 + intro-poster.png, copied to site/images) from scripts/docs/intro.html.
# Run capture-media.sh first. Requires Google Chrome, Node.js, and ffmpeg.
#
#   ./scripts/docs/make-intro.sh              full video
#   ./scripts/docs/make-intro.sh --stills     a PNG every 2 s in build/media/intro/stills, for review
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW="$ROOT/build/media/raw"
WORK="$ROOT/build/media/intro"
NODE_DIR="$ROOT/build/media/node"
IMAGES="$ROOT/docs/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -f "$RAW/pill-expanded-gpu.png" ] && [ -f "$RAW/recording-ready.png" ] \
  || { echo "Run scripts/docs/capture-media.sh first." >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)." >&2; exit 1; }
command -v node >/dev/null || { echo "Node.js is required (brew install node)." >&2; exit 1; }

if [ ! -d "$NODE_DIR/node_modules/puppeteer-core" ]; then
  mkdir -p "$NODE_DIR"
  (cd "$NODE_DIR" && npm init -y >/dev/null && npm install --silent puppeteer-core)
fi

rm -rf "$WORK"
mkdir -p "$WORK/raw"
cp "$RAW"/*.png "$WORK/raw/"
cp "$ROOT/scripts/docs/intro.html" "$WORK/intro.html"
for view in settings login; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,800 \
    --screenshot="$WORK/raw/sample-$view.png" "file://$ROOT/scripts/docs/sample-shots.html#$view" >/dev/null 2>&1
done
swiftc -O "$ROOT/scripts/make-icon.swift" -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/AppIcon.iconset" >/dev/null
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$WORK/raw/app-icon.png"

export DOTSHOT_NODE_MODULES="$NODE_DIR/node_modules"

if [ "${1:-}" = "--stills" ]; then
  mkdir -p "$WORK/stills"
  node "$ROOT/scripts/docs/render-video.mjs" "file://$WORK/intro.html" "$WORK/stills.mp4" --fps 0.5 --scale 1
  ffmpeg -loglevel error -y -i "$WORK/stills.mp4" -vsync 0 "$WORK/stills/%02d.png"
  echo "Stills in $WORK/stills"
  exit 0
fi

echo "==> rendering"
node "$ROOT/scripts/docs/render-video.mjs" "file://$WORK/intro.html" "$IMAGES/intro.mp4" --fps 30 --scale 1.5
# Poster: the moment the agent reads the delivered screenshot.
ffmpeg -loglevel error -y -ss 28.2 -i "$IMAGES/intro.mp4" -frames:v 1 -vf "scale=1280:-1" "$IMAGES/intro-poster.png"
ls -lh "$IMAGES/intro.mp4" "$IMAGES/intro-poster.png" | awk '{ print "  " $NF "  " $5 }'

mkdir -p "$ROOT/site/images"
cp "$IMAGES/intro.mp4" "$IMAGES/intro-poster.png" "$ROOT/site/images/"
