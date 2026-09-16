#!/bin/bash
# Real delivery over SSH: sends a file with the capture script, verifies it remotely, then removes it.
# Requires key-based SSH to $DOTSHOT_E2E_HOST. Does not touch your dotshot settings or clipboard history beyond one copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${DOTSHOT_E2E_HOST:?set DOTSHOT_E2E_HOST=user@host}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-e2e.XXXXXX")"
REMOTE_DIR="~/.dotshot-e2e-$$"
trap 'rm -rf "$WORK"; ssh -o BatchMode=yes "$HOST" "rm -rf $REMOTE_DIR" >/dev/null 2>&1 || true' EXIT

ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "mkdir -p $REMOTE_DIR"
printf 'name\thost\tfolder\ne2e\t%s\t%s\n' "$HOST" "$REMOTE_DIR" > "$WORK/destinations.tsv"
printf 'dotshot e2e %s\n' "$(date)" > "$WORK/e2e payload.txt"
previous_clipboard="$(pbpaste 2>/dev/null || true)"

DOTSHOT_CONFIG="$WORK/destinations.tsv" DOTSHOT_SHOTS_DIR="$WORK/Shots" \
  bash "$ROOT/scripts/dotshot-capture.sh" send e2e "$WORK/e2e payload.txt"

copied="$(pbpaste)"
printf '%s' "$previous_clipboard" | pbcopy
case "$copied" in
  /*/e2e-payload.txt) ;;
  *) echo "FAIL: clipboard should hold an absolute remote path, got '$copied'"; exit 1 ;;
esac
remote="$(ssh -o BatchMode=yes "$HOST" "cat '$copied'")"
[ "$remote" = "$(cat "$WORK/e2e payload.txt")" ] || { echo "FAIL: remote content differs"; exit 1; }
echo "e2e delivery passed: $HOST:$copied"
