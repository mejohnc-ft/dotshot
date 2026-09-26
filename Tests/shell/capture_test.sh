#!/bin/bash
# Tests for scripts/dotshot-capture.sh. scp and ssh are stubbed with a local folder standing in for the
# destination: the scp stub copies files, and the ssh stub runs the remote command with sh, so the
# rename-into-place, collision, and fallback logic run for real. osascript, pbcopy, screencapture,
# defaults, date, and the helpers are stubbed too.
# Run: ./scripts/test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TW="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-shell-tests.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$TW"' EXIT

PASS=0
FAIL=0
check() {
  local description="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $description"; fi
}
equals() { [ "$1" = "$2" ] || { echo "    expected: $2"; echo "    actual:   $1"; return 1; }; }
contains() { case "$1" in *"$2"*) return 0 ;; *) echo "    '$1' does not contain '$2'"; return 1 ;; esac; }
lacks() { case "$1" in *"$2"*) echo "    '$1' contains '$2'"; return 1 ;; *) return 0 ;; esac; }
matches() { [[ "$1" =~ $2 ]] || { echo "    '$1' does not match $2"; return 1; }; }

# The script under test sits next to stub helpers, as it does inside the app bundle.
RES="$TW/res"; mkdir -p "$RES"
cp "$ROOT/scripts/dotshot-capture.sh" "$RES/"
SCRIPT="$RES/dotshot-capture.sh"

# ── stubs ────────────────────────────────────────────────────────────────────
BIN="$TW/bin"; mkdir -p "$BIN"
CALLS="$TW/calls"
record='printf "%s" "$(basename "$0")" >> "$DOTSHOT_TEST_CALLS"; printf " [%s]" "$@" >> "$DOTSHOT_TEST_CALLS"; echo >> "$DOTSHOT_TEST_CALLS"'

cat > "$BIN/scp" <<STUB
#!/bin/bash
$record
[ "\${STUB_SCP_FAIL:-0}" = 1 ] && { echo "ssh: connect to host: Operation timed out" >&2; echo "scp: Connection closed" >&2; exit 255; }
[ "\${STUB_NO_SFTP:-0}" = 1 ] && { echo "subsystem request failed on channel 0" >&2; echo "scp: Connection closed" >&2; exit 255; }
while [ "\$1" != "--" ]; do shift; done; shift
cp "\$1" "\${2#*:}"
STUB
cat > "$BIN/ssh" <<STUB
#!/bin/bash
$record
[ "\${STUB_SSH_FAIL:-0}" = 1 ] && { echo "ssh: connect to host: Operation timed out" >&2; exit 255; }
while [ "\$1" != "--" ]; do shift; done; shift 2
HOME="\${STUB_REMOTE_HOME:-\$HOME}" /bin/sh -c "\$1"
STUB
cat > "$BIN/sftp" <<STUB
#!/bin/bash
$record
STUB
cat > "$BIN/osascript" <<STUB
#!/bin/bash
$record
STUB
cat > "$BIN/pbcopy" <<'STUB'
#!/bin/bash
cat > "$DOTSHOT_TEST_CLIPBOARD"
STUB
cat > "$BIN/screencapture" <<'STUB'
#!/bin/bash
# The last argument is the output file. Screenshots get a tiny PNG; display recordings get
# STUB_VIDEO_CONTENT; region recordings (-U) mimic macOS saving into the screenshot folder instead.
[ "${STUB_CANCEL:-0}" = 1 ] && exit 1
out="${!#}"
case " $* " in
  *" -U "*) [ -n "${STUB_LOCATION:-}" ] && printf 'region recording' > "$STUB_LOCATION/Screen Recording 2026-09-26 at 10.00.00.mov" ;;
  *" -v "*) printf '%s' "${STUB_VIDEO_CONTENT:-original recording}" > "$out" ;;
  *) printf '%s\n' "${STUB_IMAGE_CONTENT:-png}" > "$out" ;;
esac
STUB
cat > "$BIN/defaults" <<'STUB'
#!/bin/bash
[ -n "${STUB_LOCATION:-}" ] && printf '%s\n' "$STUB_LOCATION"
STUB
cat > "$BIN/date" <<'STUB'
#!/bin/bash
if [ -n "${STUB_DATE:-}" ] && [ "${1:-}" = "+%Y%m%d-%H%M%S" ]; then echo "$STUB_DATE"; else exec /bin/date "$@"; fi
STUB
cat > "$BIN/qlmanage" <<'STUB'
#!/bin/bash
sleep "${STUB_QL_SLEEP:-0}"
STUB
cat > "$RES/panel" <<'STUB'
#!/bin/bash
printf '%s\t\t\n' "${STUB_PANEL:-send}"
STUB
cat > "$RES/trim" <<'STUB'
#!/bin/bash
[ "${STUB_TRIM:-cancel}" = ok ] || exit 1
printf 'trimmed recording' > "$2"
STUB
cat > "$RES/avresize" <<'STUB'
#!/bin/bash
head -c "${STUB_RESIZED_BYTES:-5}" /dev/zero > "$2"
STUB
chmod +x "$BIN"/* "$RES"/panel "$RES"/trim "$RES"/avresize

export DOTSHOT_TEST_BIN="$BIN"
export DOTSHOT_TEST_CALLS="$CALLS"
export DOTSHOT_TEST_CLIPBOARD="$TW/clipboard"
export DOTSHOT_CONFIG="$TW/destinations.tsv"
export DOTSHOT_SHOTS_DIR="$TW/Shots"
export DOTSHOT_NAMER=local

REMOTE="$TW/remote"; mkdir -p "$REMOTE/work" "$TW/rhome/inbound"
{
  printf '# name\thost\tfolder\n'
  printf 'work\tjohn@studio\t%s/work/\n' "$REMOTE"
  printf 'home\tspark\t~/inbound\n'
  printf 'crlf \tspark\t %s/work\r\n' "$REMOTE"
  printf 'evil\t-oProxyCommand=touch%%20pwned\t/tmp\n'
  printf 'colon\thost:2222\t/tmp\n'
  printf 'relative\tspark\tinbound\n'
  printf 'bare\tspark\t~\n'
  printf 'dotdot\tspark\t/srv/../etc\n'
} > "$DOTSHOT_CONFIG"

reset() {
  : > "$CALLS"; rm -f "$DOTSHOT_TEST_CLIPBOARD"
  rm -rf "$DOTSHOT_SHOTS_DIR" "$REMOTE/work"/* "$REMOTE/work"/.[!.]* "$TW/rhome/inbound"/*
  unset STUB_SCP_FAIL STUB_NO_SFTP STUB_SSH_FAIL STUB_CANCEL STUB_REMOTE_HOME STUB_DATE STUB_LOCATION \
        STUB_PANEL STUB_TRIM STUB_RESIZED_BYTES STUB_QL_SLEEP STUB_IMAGE_CONTENT STUB_VIDEO_CONTENT
}
run() { /bin/bash "$SCRIPT" "$@" >"$TW/stdout" 2>"$TW/stderr"; }  # the app runs the system bash 3.2
clip() { cat "$DOTSHOT_TEST_CLIPBOARD" 2>/dev/null; }

# ── pure functions (sourced) ─────────────────────────────────────────────────
# shellcheck source=/dev/null
source "$SCRIPT"
check "slugify basic" equals "$(slugify 'Settings — Network Panel!')" "settings-network-panel"
check "slugify caps words at six" equals "$(slugify 'one two three four five six seven')" "one-two-three-four-five-six"
check "slugify caps length" equals "$(slugify "$(printf 'a%.0s' {1..80})")" "$(printf 'a%.0s' {1..48})"
check "slugify empty" equals "$(slugify '!!!')" ""
check "slugify first line only" equals "$(slugify $'Title\nsecond line')" "title"
check "slugify transliterates accents" equals "$(slugify 'Café naïve résumé')" "cafe-naive-resume"
check "slugify drops the word after 'password'" equals "$(slugify 'Password: Hunter2Winter! now')" "password-now"
check "slugify drops API keys" equals "$(slugify 'key sk-ant-api03-AbCdEf123456ghijkl7890 end')" "key-end"
check "slugify drops e-mail addresses" equals "$(slugify 'jane.doe@acme-health.com Patient MRN')" "patient-mrn"
check "slugify drops GitHub tokens" equals "$(slugify 'token ghp_16C7e42F292c6912E7710c838347Ae178B4a done')" "token-done"
check "slugify keeps ordinary technical words" equals "$(slugify 'gemm_bf16_tile64 MI350X rocprofv3')" "gemm-bf16-tile64-mi350x-rocprofv3"

TS=20260926-120000
check "safe filename: whitespace, timestamp" equals "$(safe_filename '/tmp/My Screen Shot.png')" "My-Screen-Shot-20260926-120000.png"
check "safe filename: strips directories" equals "$(safe_filename '../../etc/passwd')" "passwd-20260926-120000"
check "safe filename: command substitution neutralized" equals "$(safe_filename 'bug$(touch PWNED).png')" "bug-touch-PWNED-20260926-120000.png"
check "safe filename: backticks, quotes, globs" equals "$(safe_filename "a\`id\`\"q'*?[x].TXT")" "a-id-q-x-20260926-120000.txt"
check "safe filename: no leading dash" equals "$(safe_filename '-rf')" "rf-20260926-120000"
check "safe filename: no leading dot" equals "$(safe_filename '.env')" "env-20260926-120000"
check "safe filename: accents transliterated" equals "$(safe_filename 'Résumé.PDF')" "Resume-20260926-120000.pdf"
check "safe filename: bounded length" matches "$(safe_filename "$(printf 'é%.0s' {1..300}).png")" '^e{100}-20260926-120000\.png$'
check "safe filename: empty stem" equals "$(safe_filename '$$$.png')" "file-20260926-120000.png"

check "resolve trims trailing slash" bash -c "source '$SCRIPT'; resolve_destination work && [ \"\$DEST_DIR\" = '$REMOTE/work' ]"
check "resolve tolerates CRLF and spaces" bash -c "source '$SCRIPT'; resolve_destination crlf && [ \"\$DEST_DIR\" = '$REMOTE/work' ] && [ \"\$DEST_SSH\" = spark ]"
check "resolve rejects option-like host" bash -c "source '$SCRIPT'; ! resolve_destination evil"
check "resolve rejects host:port" bash -c "source '$SCRIPT'; ! resolve_destination colon"
check "resolve rejects relative folder" bash -c "source '$SCRIPT'; ! resolve_destination relative"
check "resolve rejects the bare home folder" bash -c "source '$SCRIPT'; ! resolve_destination bare"
check "resolve rejects .. in folders" bash -c "source '$SCRIPT'; ! resolve_destination dotdot"
check "resolve rejects unknown" bash -c "source '$SCRIPT'; ! resolve_destination nope"
check "resolve rejects empty" bash -c "source '$SCRIPT'; ! resolve_destination ''"

start="$(date +%s)"
run_with_timeout /dev/null 1 sleep 30
check "run_with_timeout stops a hung command" bash -c "[ $(( $(date +%s) - start )) -le 3 ]"
start="$(date +%s)"
out="$(run_with_timeout "$TW/rwt" 20 printf fast; cat "$TW/rwt")"
check "run_with_timeout returns as soon as the command finishes" bash -c "[ $(( $(date +%s) - start )) -le 2 ]"
check "run_with_timeout captures output" equals "$out" "fast"

# ── send mode ────────────────────────────────────────────────────────────────
reset
printf 'hello' > "$TW/My Notes.txt"
export STUB_DATE=20260926-101400
run send work "$TW/My Notes.txt"
check "send exits 0" equals "$?" "0"
check "send copies absolute remote path" equals "$(clip)" "$REMOTE/work/My-Notes-20260926-101400.txt"
check "send delivers the content" equals "$(cat "$REMOTE/work/My-Notes-20260926-101400.txt" 2>/dev/null)" "hello"
check "send leaves no partial file" bash -c "! ls -A '$REMOTE/work' | grep -q '\.part$'"
check "scp uses batch mode, strict host keys, keepalives, and --" contains "$(grep '^scp' "$CALLS")" "[BatchMode=yes] [-o] [StrictHostKeyChecking=yes] [-o] [ConnectTimeout=10] [-o] [ServerAliveInterval=10] [-o] [ServerAliveCountMax=3] [--]"
check "scp uploads to a hidden temporary name" matches "$(grep '^scp' "$CALLS")" "john@studio:$REMOTE/work/\.My-Notes-20260926-101400\.txt\.[0-9]+\.part\]"
check "absolute folder needs no home lookup" lacks "$(cat "$CALLS")" 'printf %s "$HOME"'

run send work "$TW/My Notes.txt"
check "same name twice keeps both files" equals "$(clip)" "$REMOTE/work/My-Notes-20260926-101400-2.txt"
check "the first delivery is untouched" equals "$(cat "$REMOTE/work/My-Notes-20260926-101400.txt")" "hello"

reset
ln -s "$TW/rhome" "$REMOTE/work/Planted-20260926-101400.txt"
printf 'new' > "$TW/Planted.txt"
export STUB_DATE=20260926-101400
run send work "$TW/Planted.txt"
check "a planted symlink is never written through" bash -c "[ -L '$REMOTE/work/Planted-20260926-101400.txt' ] && [ ! -e '$TW/rhome/Planted.txt' ]"
check "a planted symlink gets a new name" equals "$(clip)" "$REMOTE/work/Planted-20260926-101400-2.txt"

reset
export STUB_REMOTE_HOME="$TW/rhome"
run send home "$TW/My Notes.txt"
check "tilde folder resolved via remote HOME" matches "$(clip)" "^$TW/rhome/inbound/My-Notes-[0-9]{8}-[0-9]{6}\.txt$"

reset
export STUB_SSH_FAIL=1
run send home "$TW/My Notes.txt"
check "unreachable host for ~ lookup exits 1" equals "$?" "1"
check "no upload attempted when the lookup fails" bash -c "! grep -q '^scp' '$CALLS'"
check "failed lookup copies the local path, never ~" equals "$(clip)" "$TW/My Notes.txt"

reset
export STUB_SCP_FAIL=1
run send work "$TW/My Notes.txt"
check "failed send exits non-zero" equals "$?" "1"
check "failed send copies local path" equals "$(clip)" "$TW/My Notes.txt"
check "failed send notifies" contains "$(grep '^osascript' "$CALLS")" "send to work failed"
check "a connection failure isn't retried over ssh" bash -c "! grep -q 'cat >' '$CALLS'"

reset
export STUB_NO_SFTP=1
run send work "$TW/My Notes.txt"
check "destination without SFTP still receives the file" matches "$(clip)" "^$REMOTE/work/My-Notes-[0-9]{8}-[0-9]{6}\.txt$"
check "ssh fallback delivers the content" equals "$(cat "$(clip)" 2>/dev/null)" "hello"

reset
HOSTILE="$TW/bug\$(touch \${HOME}PWNED)\`id\`;x.png"
printf 'x' > "$HOSTILE"
run send work "$HOSTILE"
check "hostile name delivered" matches "$(clip)" "^$REMOTE/work/bug-touch-HOME-PWNED-id-x-[0-9]{8}-[0-9]{6}\.png$"
check "hostile name leaves no shell syntax on the clipboard" bash -c "! grep -q '[\$\`;()]' '$DOTSHOT_TEST_CLIPBOARD'"
check "hostile name ran nothing" bash -c "! ls '$TW' '$REMOTE/work' | grep -q PWNED\$"

reset
QUOTE_FILE="$TW/x\" & (do shell script \"id\") & \".png"
printf 'x' > "$QUOTE_FILE"
run send work "$QUOTE_FILE"
check "notification text is passed as argv, not AppleScript source" contains "$(grep '^osascript' "$CALLS")" "[on run argv]"

reset
ln -s "$TW/My Notes.txt" "$TW/link.png"
run send work "$TW/link.png"
check "symlinks are refused" equals "$?" "1"
check "symlinks are never uploaded" bash -c "! grep -q '^scp' '$CALLS'"

reset
mkdir -p "$TW/a folder"
run send work "$TW/a folder"
check "folders are refused with a clear message" contains "$(grep '^osascript' "$CALLS")" "Folders aren't supported"

reset
export STUB_DATE=20260926-101400
DOTSHOT_NOTIFY_STDOUT=1 run send work "$TW/My Notes.txt"
check "app mode prints notification line" equals "$(cat "$TW/stdout")" $'dotshot-notify\tSent to work\t'"$REMOTE/work/My-Notes-20260926-101400.txt (path copied)"
check "app mode skips osascript" bash -c "! grep -q '^osascript' '$CALLS'"

reset
run send missing "$TW/My Notes.txt"
check "unknown destination exits 1" equals "$?" "1"
check "unknown destination asks for setup" contains "$(cat "$CALLS")" "dotshot needs setup"
check "unknown destination never calls scp" bash -c "! grep -q '^scp' '$CALLS'"

reset
run send evil "$TW/My Notes.txt"
check "unsafe destination never calls scp" bash -c "! grep -q '^scp' '$CALLS'"

reset
run send work "$TW/does-not-exist.png"
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
check "image named with timestamp" matches "$(basename "$shot")" '^[a-z0-9-]+-[0-9]{8}-[0-9]{6}\.png$'
check "image path copied" equals "$(clip)" "$REMOTE/work/$(basename "$shot")"
check "Shots folder is private" equals "$(stat -f %Lp "$DOTSHOT_SHOTS_DIR")" "700"
check "local capture is private" equals "$(stat -f %Lp "$shot")" "600"
check "no temporary files left in /tmp" bash -c "! ls -d /tmp/dotshot.* 2>/dev/null | xargs -I{} find {} -newer '$CALLS' 2>/dev/null | grep -q ."

reset
export STUB_DATE=20260926-101500
STUB_IMAGE_CONTENT=red run image work
STUB_IMAGE_CONTENT=blue run image work
check "two captures in the same second keep both locally" equals "$(ls "$DOTSHOT_SHOTS_DIR"/*.png | wc -l | tr -d ' ')" "2"
check "two captures in the same second keep both remotely" equals "$(ls "$REMOTE/work"/*.png | wc -l | tr -d ' ')" "2"
check "the second capture's content survives" bash -c "cat '$REMOTE/work'/*.png | grep -q blue && cat '$REMOTE/work'/*.png | grep -q red"

reset
export STUB_CANCEL=1
run image work
check "cancelled capture exits 0" equals "$?" "0"
check "cancelled capture sends nothing" bash -c "! grep -q '^scp' '$CALLS'"
check "cancelled capture leaves no file" bash -c "! ls '$DOTSHOT_SHOTS_DIR'/*.png >/dev/null 2>&1"

# ── video mode ───────────────────────────────────────────────────────────────
reset
run video work 1
check "display recording is sent" matches "$(clip)" "^$REMOTE/work/rec-[0-9]{8}-[0-9]{6}\.mov$"
check "display recording content" equals "$(cat "$(clip)" 2>/dev/null)" "original recording"

reset
export STUB_PANEL=trim STUB_TRIM=ok
run video work 1
check "Trim sends the trimmed recording" equals "$(cat "$(clip)" 2>/dev/null)" "trimmed recording"

reset
export STUB_PANEL=trim STUB_TRIM=cancel
run video work 1
check "cancelling Trim sends nothing" bash -c "! grep -q '^scp' '$CALLS'"
check "cancelling Trim keeps the recording" bash -c "ls '$DOTSHOT_SHOTS_DIR'/rec-*.mov >/dev/null 2>&1"
check "cancelling Trim says so" contains "$(grep '^osascript' "$CALLS")" "Recording kept, not sent"

reset
export STUB_PANEL=cancel
run video work 1
check "Cancel sends nothing" bash -c "! grep -q '^scp' '$CALLS'"
check "Cancel keeps the recording" bash -c "ls '$DOTSHOT_SHOTS_DIR'/rec-*.mov >/dev/null 2>&1"

reset
export STUB_PANEL=resize STUB_RESIZED_BYTES=5
run video work 1
check "Resize sends the smaller file" equals "$(stat -f %z "$(clip)" 2>/dev/null)" "5"

reset
export STUB_PANEL=resize STUB_RESIZED_BYTES=100000
run video work 1
check "Resize keeps the original when it isn't smaller" equals "$(cat "$(clip)" 2>/dev/null)" "original recording"

reset
export STUB_QL_SLEEP=60
start="$(date +%s)"
run video work 1
check "a hung poster step can't block delivery" bash -c "[ $(( $(date +%s) - start )) -le 20 ] && grep -q '^scp' '$CALLS'"

reset
LOC="$TW/location"; rm -rf "$LOC"; mkdir -p "$LOC"
export STUB_LOCATION="$LOC"
sleep 1
printf 'family video' > "$LOC/unrelated-family-video.mp4"
touch -t 202601010000 "$LOC/unrelated-family-video.mp4"
run video work
check "region recording saved by macOS is found and sent" equals "$(cat "$(clip)" 2>/dev/null)" "region recording"
check "unrelated videos in the screenshot folder are left alone" test -f "$LOC/unrelated-family-video.mp4"

reset
LOC="$TW/location2"; mkdir -p "$LOC"
export STUB_LOCATION="$LOC" STUB_CANCEL=1
printf 'family video' > "$LOC/unrelated.mov"
run video work
check "cancelled region recording never grabs another file" bash -c "! grep -q '^scp' '$CALLS' && [ -f '$LOC/unrelated.mov' ]"

# ── setup commands (list / add / check) ──────────────────────────────────────
reset
SETUP_CFG="$TW/setup.tsv"; rm -f "$SETUP_CFG"
setup() { DOTSHOT_CONFIG="$SETUP_CFG" /bin/bash "$SCRIPT" "$@" >"$TW/stdout" 2>"$TW/stderr"; }
setup add gpu dev@gpu-box '~/inbound'
check "add saves a destination" equals "$(DOTSHOT_CONFIG="$SETUP_CFG" /bin/bash "$SCRIPT" list)" $'gpu\tdev@gpu-box\t~/inbound'
setup add gpu dev@other '/srv/in/'
check "add replaces a destination of the same name" equals "$(DOTSHOT_CONFIG="$SETUP_CFG" /bin/bash "$SCRIPT" list)" $'gpu\tdev@other\t/srv/in'
setup add bad 'host:22' /tmp
check "add rejects host:port" equals "$?" "2"
setup add home spark '~'
check "add rejects the bare home folder" equals "$?" "2"
setup add 'a b' spark /tmp/x
check "add rejects names with spaces" equals "$?" "2"

mkdir -p "$TW/rhome"; export STUB_REMOTE_HOME="$TW/rhome"
RHOME="$(cd "$TW/rhome" && pwd -P)"  # check reports the physical path (/private/var/…)
setup add box john@studio '~/checked'
setup check box
check "check exits 0 for a working destination" equals "$?" "0"
check "check reports the absolute folder" equals "$(cat "$TW/stdout")" "ok box john@studio:$RHOME/checked"
check "check saves the absolute folder" contains "$(DOTSHOT_CONFIG="$SETUP_CFG" /bin/bash "$SCRIPT" list)" $'box\tjohn@studio\t'"$RHOME/checked"
check "check creates a private folder" equals "$(stat -f %Lp "$TW/rhome/checked")" "700"
chmod 777 "$TW/rhome/checked"
setup check box
check "check refuses a folder others can write to" contains "$(cat "$TW/stderr")" "other accounts can write to it"
export STUB_SSH_FAIL=1
setup check box
check "check explains an unreachable host" contains "$(cat "$TW/stderr")" "timed out"
unset STUB_SSH_FAIL STUB_REMOTE_HOME

echo "$PASS/$((PASS + FAIL)) shell checks passed"
[ "$FAIL" -eq 0 ]
