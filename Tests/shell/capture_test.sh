#!/bin/bash
# Tests for scripts/dotshot-capture.sh. ssh, scp, osascript, pbcopy, and screencapture are stubbed.
# Run: ./scripts/test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/dotshot-capture.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-shell-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check() {
  local description="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $description"; fi
}
equals() { [ "$1" = "$2" ] || { echo "    expected: $2"; echo "    actual:   $1"; return 1; }; }
contains() { case "$1" in *"$2"*) return 0 ;; *) echo "    '$1' does not contain '$2'"; return 1 ;; esac; }

# ── stubs ────────────────────────────────────────────────────────────────────
BIN="$WORK/bin"; mkdir -p "$BIN"
CALLS="$WORK/calls"
cat > "$BIN/scp" <<'STUB'
#!/bin/bash
printf 'scp' >> "$DOTSHOT_TEST_CALLS"; printf ' [%s]' "$@" >> "$DOTSHOT_TEST_CALLS"; echo >> "$DOTSHOT_TEST_CALLS"
[ "${STUB_SCP_FAIL:-0}" = 1 ] && { echo "ssh: connect to host: Connection refused" >&2; exit 1; }
exit 0
STUB
cat > "$BIN/ssh" <<'STUB'
#!/bin/bash
printf 'ssh' >> "$DOTSHOT_TEST_CALLS"; printf ' [%s]' "$@" >> "$DOTSHOT_TEST_CALLS"; echo >> "$DOTSHOT_TEST_CALLS"
printf '%s' "${STUB_REMOTE_HOME:-/home/agent}"
STUB
cat > "$BIN/osascript" <<'STUB'
#!/bin/bash
printf 'osascript' >> "$DOTSHOT_TEST_CALLS"; printf ' [%s]' "$@" >> "$DOTSHOT_TEST_CALLS"; echo >> "$DOTSHOT_TEST_CALLS"
STUB
cat > "$BIN/pbcopy" <<'STUB'
#!/bin/bash
cat > "$DOTSHOT_TEST_CLIPBOARD"
STUB
cat > "$BIN/screencapture" <<'STUB'
#!/bin/bash
# The last argument is the output file; write a tiny PNG unless the test simulates Esc.
[ "${STUB_CANCEL:-0}" = 1 ] && exit 1
out="${!#}"
printf '\x89PNG\r\n\x1a\n' > "$out"
STUB
chmod +x "$BIN"/*

export DOTSHOT_TEST_BIN="$BIN"
export DOTSHOT_TEST_CALLS="$CALLS"
export DOTSHOT_TEST_CLIPBOARD="$WORK/clipboard"
export DOTSHOT_CONFIG="$WORK/destinations.tsv"
export DOTSHOT_SHOTS_DIR="$WORK/Shots"
export DOTSHOT_NAMER=local

printf '# name\thost\tfolder\n' > "$DOTSHOT_CONFIG"
printf 'work\tjohn@studio\t/Users/john/inbound/\n' >> "$DOTSHOT_CONFIG"
printf 'home\tspark\t~/inbound\n' >> "$DOTSHOT_CONFIG"
printf 'evil\t-oProxyCommand=touch%%20pwned\t/tmp\n' >> "$DOTSHOT_CONFIG"
printf 'relative\tspark\tinbound\n' >> "$DOTSHOT_CONFIG"

reset() { : > "$CALLS"; rm -f "$DOTSHOT_TEST_CLIPBOARD"; unset STUB_SCP_FAIL STUB_CANCEL STUB_REMOTE_HOME; }
run() { bash "$SCRIPT" "$@" >"$WORK/stdout" 2>"$WORK/stderr"; }

# ── pure functions (sourced) ─────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$SCRIPT"
check "slugify basic" equals "$(slugify 'Settings — Network Panel!')" "settings-network-panel"
check "slugify caps words at six" equals "$(slugify 'one two three four five six seven')" "one-two-three-four-five-six"
check "slugify caps length" equals "$(slugify "$(printf 'a%.0s' {1..80})")" "$(printf 'a%.0s' {1..48})"
check "slugify empty" equals "$(slugify '!!!')" ""
check "slugify first line only" equals "$(slugify $'Title\nsecond line')" "title"
check "safe filename replaces whitespace" equals "$(safe_filename '/tmp/My Screen Shot.png')" "My-Screen-Shot.png"
check "safe filename strips directories" equals "$(safe_filename '../../etc/passwd')" "passwd"
check "resolve trims trailing slash" bash -c "source '$SCRIPT'; resolve_destination work && [ \"\$DEST_DIR\" = /Users/john/inbound ]"
check "resolve rejects option-like host" bash -c "source '$SCRIPT'; ! resolve_destination evil"
check "resolve rejects relative folder" bash -c "source '$SCRIPT'; ! resolve_destination relative"
check "resolve rejects unknown" bash -c "source '$SCRIPT'; ! resolve_destination nope"
check "resolve rejects empty" bash -c "source '$SCRIPT'; ! resolve_destination ''"

# ── send mode ────────────────────────────────────────────────────────────────
reset
printf 'hello' > "$WORK/My Notes.txt"
run send work "$WORK/My Notes.txt"
check "send exits 0" equals "$?" "0"
check "send copies absolute remote path" equals "$(cat "$DOTSHOT_TEST_CLIPBOARD")" "/Users/john/inbound/My-Notes.txt"
check "send uses batch mode scp with -- separator" contains "$(grep '^scp' "$CALLS")" "[BatchMode=yes] [-o] [ConnectTimeout=10] [--] [$WORK/My Notes.txt] [john@studio:/Users/john/inbound/My-Notes.txt]"
check "absolute folder needs no ssh lookup" bash -c "! grep -q '^ssh' '$CALLS'"

reset
export STUB_REMOTE_HOME=/home/mejohnc
run send home "$WORK/My Notes.txt"
check "tilde folder resolved via remote HOME" equals "$(cat "$DOTSHOT_TEST_CLIPBOARD")" "/home/mejohnc/inbound/My-Notes.txt"

reset
export STUB_SCP_FAIL=1
run send work "$WORK/My Notes.txt"
check "failed send exits non-zero" equals "$?" "1"
check "failed send copies local path" equals "$(cat "$DOTSHOT_TEST_CLIPBOARD")" "$WORK/My Notes.txt"
check "failed send notifies" contains "$(grep '^osascript' "$CALLS")" "send to work failed"

reset
QUOTE_FILE="$WORK/x\" & (do shell script \"id\") & \".png"
printf 'x' > "$QUOTE_FILE"
run send work "$QUOTE_FILE"
check "notification text is passed as argv, not AppleScript source" contains "$(grep '^osascript' "$CALLS")" "[on run argv]"
check "quoted file name delivered intact" contains "$(cat "$DOTSHOT_TEST_CLIPBOARD")" 'x"-&-(do-shell-script-"id")-&-".png'

reset
DOTSHOT_NOTIFY_STDOUT=1 run send work "$WORK/My Notes.txt"
check "app mode prints notification line" equals "$(cat "$WORK/stdout")" $'dotshot-notify\tSent to work\t/Users/john/inbound/My-Notes.txt (path copied)'
check "app mode skips osascript" bash -c "! grep -q '^osascript' '$CALLS'"

reset
run send missing "$WORK/My Notes.txt"
check "unknown destination exits 1" equals "$?" "1"
check "unknown destination asks for setup" contains "$(cat "$CALLS")" "dotshot needs setup"
check "unknown destination never calls scp" bash -c "! grep -q '^scp' '$CALLS'"

reset
run send evil "$WORK/My Notes.txt"
check "unsafe destination never calls scp" bash -c "! grep -q '^scp' '$CALLS'"

reset
run send work "$WORK/does-not-exist.png"
check "missing file exits 1" equals "$?" "1"

reset
run bogus work
check "unknown mode exits 2" equals "$?" "2"

# ── image mode ───────────────────────────────────────────────────────────────
reset
run image work
check "image exits 0" equals "$?" "0"
shot="$(ls "$DOTSHOT_SHOTS_DIR"/*.png 2>/dev/null | head -1)"
check "image kept locally in Shots" test -f "$shot"
check "image named with timestamp" bash -c "[[ '$(basename "$shot")' =~ ^[a-z0-9-]+-[0-9]{8}-[0-9]{6}\.png$ ]]"
check "image path copied" equals "$(cat "$DOTSHOT_TEST_CLIPBOARD")" "/Users/john/inbound/$(basename "$shot")"

reset
rm -f "$DOTSHOT_SHOTS_DIR"/*.png
export STUB_CANCEL=1
run image work
check "cancelled capture exits 0" equals "$?" "0"
check "cancelled capture sends nothing" bash -c "! grep -q '^scp' '$CALLS'"
check "cancelled capture leaves no file" bash -c "! ls '$DOTSHOT_SHOTS_DIR'/*.png >/dev/null 2>&1"

echo "$PASS/$((PASS + FAIL)) shell checks passed"
[ "$FAIL" -eq 0 ]
