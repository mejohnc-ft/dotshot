#!/bin/bash
# Render the intro video (docs/images/intro.mp4 + intro-poster.png, copied to site/images) from scripts/docs/intro.html.
# Run capture-media.sh first. Requires Google Chrome, Node.js, and ffmpeg.
#
#   ./scripts/docs/make-intro.sh              full video with its generated soundtrack
#   ./scripts/docs/make-intro.sh --audio      regenerate only the soundtrack and remux (reuses the last render)
#   ./scripts/docs/make-intro.sh --stills     a PNG every 2 s in build/media/intro/stills, for review
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW="$ROOT/build/media/raw"
WORK="$ROOT/build/media/intro"
RENDER="$ROOT/build/media/intro-render"   # silent video + sound cues, kept for --audio
NODE_DIR="$ROOT/build/media/node"
IMAGES="$ROOT/docs/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -f "$RAW/pill-expanded-rocm.png" ] && [ -f "$RAW/recording-ready.png" ] \
  || { echo "Run scripts/docs/capture-media.sh first." >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)." >&2; exit 1; }
command -v node >/dev/null || { echo "Node.js is required (brew install node)." >&2; exit 1; }

if [ ! -d "$NODE_DIR/node_modules/puppeteer-core" ]; then
  mkdir -p "$NODE_DIR"
  (cd "$NODE_DIR" && npm init -y >/dev/null && npm install --silent puppeteer-core)
fi

export DOTSHOT_NODE_MODULES="$NODE_DIR/node_modules"

# soundtrack: synthesize stems from the scene's cues, then mix (reverb on the music) and mux.
soundtrack() {
  echo "==> soundtrack"
  node "$ROOT/scripts/docs/soundtrack.mjs" "$RENDER/intro.cues.json" "$RENDER/music.wav" "$RENDER/sfx.wav"
  ffmpeg -loglevel error -y -i "$RENDER/intro.mp4" -i "$RENDER/music.wav" -i "$RENDER/sfx.wav" -filter_complex \
    "[1:a]highpass=f=45,equalizer=f=110:t=q:w=1:g=-4,equalizer=f=2800:t=q:w=1.4:g=3,aecho=0.8:0.6:90|180|310:0.28|0.18|0.1,lowpass=f=11000[m];[2:a]aecho=0.9:0.5:40|75:0.16|0.08,volume=2.2[s];[m][s]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.75:level=false[a]" \
    -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$IMAGES/intro.mp4"
}

if [ "${1:-}" = "--audio" ]; then
  [ -f "$RENDER/intro.mp4" ] && [ -f "$RENDER/intro.cues.json" ] || { echo "Run make-intro.sh once without --audio first." >&2; exit 1; }
  soundtrack
  cp "$IMAGES/intro.mp4" "$ROOT/site/images/"
  ls -lh "$IMAGES/intro.mp4" | awk '{ print "  " $NF "  " $5 }'
  exit 0
fi

rm -rf "$WORK"
mkdir -p "$WORK/raw" "$RENDER"
cp "$RAW"/*.png "$WORK/raw/"
cp "$ROOT/scripts/docs/intro.html" "$WORK/intro.html"
for view in settings login training rocprof; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,800 \
    --screenshot="$WORK/raw/sample-$view.png" "file://$ROOT/scripts/docs/sample-shots.html#$view" >/dev/null 2>&1
done
swiftc -O "$ROOT/scripts/make-icon.swift" -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/AppIcon.iconset" >/dev/null
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$WORK/raw/app-icon.png"

if [ "${1:-}" = "--stills" ]; then
  mkdir -p "$WORK/stills"
  node "$ROOT/scripts/docs/render-video.mjs" "file://$WORK/intro.html" "$WORK/stills.mp4" --fps 0.5 --scale 1
  ffmpeg -loglevel error -y -i "$WORK/stills.mp4" -vsync 0 "$WORK/stills/%02d.png"
  echo "Stills in $WORK/stills"
  exit 0
fi

echo "==> rendering"
node "$ROOT/scripts/docs/render-video.mjs" "file://$WORK/intro.html" "$RENDER/intro.mp4" --fps 30 --scale 1.5
soundtrack
# Poster: the moment the agent reads the delivered screenshot.
ffmpeg -loglevel error -y -ss 29.9 -i "$IMAGES/intro.mp4" -frames:v 1 -vf "scale=1280:-1" "$IMAGES/intro-poster.png"
# README thumbnail: GitHub can't play repository videos inline, so the README links this image to the site.
cat > "$WORK/play.html" <<HTML
<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;width:1280px;height:720px;overflow:hidden;font:600 26px -apple-system,sans-serif}
img{position:absolute;inset:0;width:100%}
.d{position:absolute;inset:0;background:radial-gradient(closest-side,rgba(0,26,34,.86),rgba(0,26,34,.55))}
.c{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:22px;color:#fdf6e3}
.p{width:128px;height:128px;border-radius:50%;background:#b58900;display:grid;place-items:center;box-shadow:0 0 0 12px rgba(181,137,0,.28),0 20px 50px rgba(0,0,0,.5)}
.p i{margin-left:10px;border-left:44px solid #1b1500;border-top:27px solid transparent;border-bottom:27px solid transparent}
small{font-weight:500;font-size:19px;color:#c9c3ad}
</style><img src="file://$IMAGES/intro-poster.png"><div class="d"></div><div class="c"><div class="p"><i></i></div>Watch the 80-second intro<small>Spark cluster · ROCm cluster · Dev Mac · NAS</small></div>
HTML
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 --window-size=1280,720 \
  --screenshot="$IMAGES/intro-thumb.png" "file://$WORK/play.html" >/dev/null 2>&1
ls -lh "$IMAGES/intro.mp4" "$IMAGES/intro-poster.png" "$IMAGES/intro-thumb.png" | awk '{ print "  " $NF "  " $5 }'

mkdir -p "$ROOT/site/images"
cp "$IMAGES/intro.mp4" "$IMAGES/intro-poster.png" "$ROOT/site/images/"
