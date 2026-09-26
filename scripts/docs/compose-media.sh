#!/bin/bash
# Compose raw window captures into README and site images.
# Run ./scripts/docs/capture-media.sh first. Requires Google Chrome.
#
#   ./scripts/docs/compose-media.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW="$ROOT/build/media/raw"
WORK="$ROOT/build/media/compose"
IMAGES="$ROOT/docs/images"
SITE_IMAGES="$ROOT/site/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -f "$RAW/pill-expanded.png" ] || { echo "Run scripts/docs/capture-media.sh first." >&2; exit 1; }
[ -x "$CHROME" ] || { echo "Google Chrome is required." >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/raw" "$IMAGES" "$SITE_IMAGES"
cp "$RAW"/*.png "$WORK/raw/"
cp "$ROOT/scripts/docs/compose.html" "$WORK/compose.html"

# chrome_shot <url> <css-width> <css-height> <output> [scale]
chrome_shot() {
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="${5:-2}" \
    --window-size="$2,$3" --screenshot="$4" "$1" >/dev/null 2>&1
}

# A sharp @2x copy of the sample app page for the hero's browser window.
chrome_shot "file://$ROOT/scripts/docs/sample-shots.html#settings" 1280 800 "$WORK/raw/sample-settings.png"

# layout:css-width:css-height:scale — large setup windows render at 1.5x to stay light.
for spec in hero:1200:675:2 pill:1200:560:2 drop:1000:560:2 picker:1080:640:2 \
            setup-welcome:1040:780:1.5 setup-permissions:1040:780:1.5 setup-connect:1040:780:1.5 \
            setup-destinations:1040:780:1.5 setup-test:1040:780:1.5 setup-login:1040:780:1.5 \
            setup-appearance:1040:780:1.5 setup-done:1040:780:1.5 recording-ready:800:560:2; do
  IFS=: read -r layout width height scale <<< "$spec"
  case "$layout" in
    drop) name="drop-targets" ;;
    picker) name="recording-picker" ;;
    *) name="$layout" ;;
  esac
  chrome_shot "file://$WORK/compose.html#$layout" "$width" "$height" "$IMAGES/$name.png" "$scale"
  echo "    docs/images/$name.png"
done

# Keep PNGs light for README and site loads: quantize to a dithered palette when large.
shrink() {
  local file="$1" tmp="$1.tmp.png"
  [ "$(stat -f %z "$file")" -gt 650000 ] || return 0
  ffmpeg -loglevel error -y -i "$file" \
    -vf "split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" "$tmp"
  mv "$tmp" "$file"
}
# 1200×630 social preview card (Open Graph / GitHub) from the hero, keeping the wordmark.
ffmpeg -loglevel error -y -i "$IMAGES/hero.png" -vf "scale=1200:-1:flags=lanczos,crop=1200:630:0:45" "$IMAGES/og-image.png"
echo "    docs/images/og-image.png"

for file in "$IMAGES"/*.png; do shrink "$file"; done


rm -f "$IMAGES/onboarding-welcome.png"

for name in hero pill drop-targets recording-picker recording-ready og-image \
            setup-welcome setup-permissions setup-connect setup-destinations setup-test setup-login setup-appearance setup-done; do
  cp "$IMAGES/$name.png" "$SITE_IMAGES/$name.png"
done
for name in demo.gif demo.mp4 demo-poster.png intro.mp4 intro-poster.png; do
  [ -f "$IMAGES/$name" ] && cp "$IMAGES/$name" "$SITE_IMAGES/$name"
done
cp "$RAW/pill-collapsed.png" "$SITE_IMAGES/nub.png"
echo "Composed images in docs/images and site/images."
