#!/bin/bash
# Real delivery over SSH: sends a file with the capture script, verifies it remotely, then removes it.
# Requires key-based SSH to $DOTSHOT_E2E_HOST. Does not touch your dotshot settings or clipboard history beyond one copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${DOTSHOT_E2E_HOST:?set DOTSHOT_E2E_HOST=user@host}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-e2e.XXXXXX")"
# shellcheck disable=SC2088  # expanded on the destination
REMOTE_DIR="~/.dotshot-e2e-$$"
trap 'rm -rf "$WORK"; ssh -o BatchMode=yes "$HOST" "rm -rf $REMOTE_DIR" >/dev/null 2>&1 || true' EXIT

ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "mkdir -p $REMOTE_DIR"
printf 'name\thost\tfolder\ne2e\t%s\t%s\n' "$HOST" "$REMOTE_DIR" > "$WORK/destinations.tsv"
printf 'dotshot e2e %s\n' "$(date)" > "$WORK/e2e payload.txt"
previous_clipboard="$(pbpaste 2>/dev/null || true)"

send() {
  DOTSHOT_CONFIG="$WORK/destinations.tsv" DOTSHOT_SHOTS_DIR="$WORK/Shots" \
    /bin/bash "$ROOT/scripts/dotshot-capture.sh" send e2e "$WORK/e2e payload.txt"
  pbpaste
}
first="$(send)"
second="$(send)"
printf '%s' "$previous_clipboard" | pbcopy

case "$first" in
  /*/e2e-payload-[0-9]*-[0-9]*.txt) ;;
  *) echo "FAIL: clipboard should hold an absolute remote path, got '$first'"; exit 1 ;;
esac
[ "$second" != "$first" ] || { echo "FAIL: a second send overwrote the first ($first)"; exit 1; }
remote="$(ssh -o BatchMode=yes "$HOST" "cat '$first'")"
[ "$remote" = "$(cat "$WORK/e2e payload.txt")" ] || { echo "FAIL: remote content differs"; exit 1; }
leftovers="$(ssh -o BatchMode=yes "$HOST" "ls -A $REMOTE_DIR | grep -c '\.part\$' || true")"
[ "$leftovers" = 0 ] || { echo "FAIL: $leftovers partial upload(s) left behind"; exit 1; }
mode="$(ssh -o BatchMode=yes "$HOST" "stat -c %a '$first' 2>/dev/null || stat -f %Lp '$first'")"
[ "$mode" = 600 ] || { echo "FAIL: delivered file is mode $mode, expected 600"; exit 1; }
echo "e2e delivery passed: $HOST:$first (and $second), no partial files, mode 600"
