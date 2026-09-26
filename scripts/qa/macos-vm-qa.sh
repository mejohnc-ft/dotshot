#!/bin/bash
# First-install QA on a clean macOS VM (Tart, Apple's Virtualization framework), against a clean Linux
# destination in Apple's `container`. Covers what only a fresh Mac can show: Gatekeeper on a quarantined
# download, the installed app's architecture, and scripted setup (add/check/send) with the Mac's own
# tools. The GUI steps (first launch, the Screen Recording alert, setup screens) are listed at the end for
# a person to click through in the VM window.
#
#   ./scripts/qa/macos-vm-qa.sh [path/to/dotshot-<version>.dmg]    default: build/release/<version>/…dmg
#
# Requires: Apple silicon, tart (https://github.com/cirruslabs/tart/releases), container, ~25 GB for the
# macOS 14 image (the oldest macOS dotshot supports). Leaves the VM running for the GUI checks; stop it
# with `tart stop dotshot-qa-sonoma`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="${1:-$ROOT/build/release/$VERSION/dotshot-$VERSION.dmg}"
TART="$(command -v tart || echo "$HOME/.local/bin/tart")"
VM=dotshot-qa-sonoma
IMAGE=ghcr.io/cirruslabs/macos-sonoma-base:latest
DEST=dotshot-qa-vmdest
SHARE="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-vm-share.XXXXXX")"

[ -x "$TART" ] || { echo "tart is required: https://github.com/cirruslabs/tart/releases" >&2; exit 1; }
[ -f "$DMG" ] || { echo "No DMG at $DMG; run ./scripts/release.sh first." >&2; exit 1; }
cp "$DMG" "$SHARE/dotshot.dmg"
cp "$ROOT/scripts/qa/destination/Containerfile" "$SHARE/"

echo "==> VM (macOS 14)"
"$TART" list | grep -q " $VM " || "$TART" clone "$IMAGE" "$VM" || exit 1
"$TART" stop "$VM" >/dev/null 2>&1
open -a "$(dirname "$(dirname "$(dirname "$(readlink -f "$TART")")")")" --args run "$VM" "--dir=qa:$SHARE:ro"
for _ in $(seq 1 60); do "$TART" ip "$VM" >/dev/null 2>&1 && break; sleep 3; done
guest() { "$TART" exec -i "$VM" bash -s; }

echo "==> destination (Linux container, SSH published only on the VM network)"
container image inspect dotshot-qa-dest:latest >/dev/null 2>&1 \
  || container build -q -t dotshot-qa-dest:latest -f "$ROOT/scripts/qa/destination/Containerfile" "$ROOT/scripts/qa/destination" >/dev/null
GATEWAY="$(echo 'route -n get default | awk "/gateway/{print \$2}"' | guest)"
container rm -f "$DEST" >/dev/null 2>&1
container run -d --name "$DEST" -p "$GATEWAY:2222:22" dotshot-qa-dest:latest >/dev/null || exit 1
sleep 4

echo "==> install like a download, then ask Gatekeeper"
guest <<'EOF'
set -e
Q="0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)"
cp "/Volumes/My Shared Files/qa/dotshot.dmg" ~/Downloads/ && xattr -w com.apple.quarantine "$Q" ~/Downloads/dotshot.dmg
spctl -a -t open --context context:primary-signature -vv ~/Downloads/dotshot.dmg 2>&1 | sed 's/^/  dmg: /'
MNT=$(hdiutil attach -nobrowse ~/Downloads/dotshot.dmg | awk -F'\t' '/Volumes/{print $NF}')
rm -rf /Applications/dotshot.app && ditto "$MNT/dotshot.app" /Applications/dotshot.app && hdiutil detach -quiet "$MNT"
xattr -w com.apple.quarantine "$Q" /Applications/dotshot.app
spctl -a -vv /Applications/dotshot.app 2>&1 | sed 's/^/  app: /'
xcrun stapler validate /Applications/dotshot.app 2>&1 | tail -1 | sed 's/^/  staple: /'
lipo -archs /Applications/dotshot.app/Contents/MacOS/dotshot | sed 's/^/  archs: /'
EOF

echo "==> scripted setup from the VM (add / check / send)"
PUB="$(printf '%s\n' "GW=$GATEWAY" 'set -e
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
grep -q "^Host qa-dest" ~/.ssh/config 2>/dev/null || printf "Host qa-dest\n  HostName %s\n  Port 2222\n  User dev\n" "$GW" >> ~/.ssh/config
ssh-keygen -R "[$GW]:2222" >/dev/null 2>&1 || true
ssh-keyscan -T 5 -t ed25519 -p 2222 "$GW" 2>/dev/null >> ~/.ssh/known_hosts
cat ~/.ssh/id_ed25519.pub' | guest)"
seen="$(printf '%s\n' "ssh-keyscan -T 5 -t ed25519 -p 2222 $GATEWAY 2>/dev/null | ssh-keygen -lf - | awk '{print \$2}'" | guest)"
real="$(container exec "$DEST" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
[ "$seen" = "$real" ] && echo "  host key fingerprint matches ($real)" || { echo "  host key MISMATCH: $seen vs $real" >&2; exit 1; }
printf '%s\n' "$PUB" | container exec -i "$DEST" su dev -c 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
guest <<'EOF'
DS=/Applications/dotshot.app/Contents/Resources/dotshot-capture.sh
"$DS" add qa qa-dest '~/inbound' | sed 's/^/  /'
"$DS" check qa | sed 's/^/  /'
printf 'hello from macOS 14\n' > "/tmp/QA Note.txt"; : > '/tmp/bug$(touch PWNED)`id`.png'
for f in "/tmp/QA Note.txt" '/tmp/bug$(touch PWNED)`id`.png'; do "$DS" send qa "$f" && echo "  sent → $(pbpaste)"; done
EOF
echo "  destination: $(container exec "$DEST" su dev -c 'stat -c "%a %n" ~/inbound ~/inbound/* | tr "\n" " "')"
echo "  PWNED files on destination: $(container exec "$DEST" su dev -c 'ls ~ ~/inbound | grep -c "PWNED$" || true')"

cat <<EOF

==> Now in the VM window (password: admin):
  1. open /Applications/dotshot.app → setup opens; text is readable in light mode
  2. Permission → Request Permission → the macOS alert appears ABOVE setup → Open System Settings
  3. Turn dotshot on, quit and reopen when asked, press Check Again → "Permission granted"
  4. Destinations: qa is listed → Test → Ready
  5. ⌃⌥⌘S → drag → "Sent to qa" → paste the path; ⌃⌥⌘V → record → Trim → Send
Clean up: tart stop $VM; container rm -f $DEST
EOF
