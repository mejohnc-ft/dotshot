#!/bin/bash
# New-user setup QA against clean destination machines running in Apple's `container` (Linux VMs).
#
# Walks through setup the way a new user would, using the script inside a freshly built dotshot.app:
# unknown host key → compare fingerprints → key not authorized → authorize → add/check → send →
# collisions, hostile names, shared folders, a server without SFTP, an unreachable host, and the
# dotshot-inbox skill's commands on the destination.
#
#   ./scripts/qa/setup-qa.sh            build images if needed, run, clean up
#   KEEP=1 ./scripts/qa/setup-qa.sh     leave the containers running afterwards
#
# Requires: macOS 26 on Apple silicon, `container` (brew install container) with a kernel configured
# (`container system kernel set --recommended`), and an SSH key in ~/.ssh. Your dotshot settings are not
# touched. The containers' host keys are added to ~/.ssh/known_hosts during the run and removed after.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-setup-qa.XXXXXX")"
APP="$ROOT/build/qa-container/dotshot.app"
DS="$APP/Contents/Resources/dotshot-capture.sh"
export DOTSHOT_CONFIG="$WORK/destinations.tsv" DOTSHOT_SHOTS_DIR="$WORK/Shots"
IMAGE=dotshot-qa-dest:latest
IMAGE_NOSFTP=dotshot-qa-dest-nosftp:latest
MAIN=dotshot-qa-main
NOSFTP=dotshot-qa-nosftp
IPS=()
# shellcheck disable=SC2088  # meant literally: dotshot expands ~ on the destination
INBOX='~/inbound'

PASS=0; FAIL=0; REPORT="$WORK/report.md"
check() { local d="$1"; shift; if "$@"; then PASS=$((PASS + 1)); echo "  ✓ $d"; echo "| ✓ | $d |" >> "$REPORT"; else FAIL=$((FAIL + 1)); echo "  ✗ $d"; echo "| ✗ | $d |" >> "$REPORT"; fi; }
has() { case "$1" in *"$2"*) return 0 ;; *) echo "      '$1' lacks '$2'"; return 1 ;; esac; }
is() { [ "$1" = "$2" ] || { echo "      expected '$2', got '$1'"; return 1; }; }
step() { echo; echo "== $*"; printf '\n**%s**\n\n| | Check |\n| --- | --- |\n' "$*" >> "$REPORT"; }
run() { /bin/bash "$DS" "$@" >"$WORK/out" 2>"$WORK/err"; }
dexec() { container exec "$1" su dev -c "$2"; }

previous_clipboard="$(pbpaste 2>/dev/null || true)"
cleanup() {
  printf '%s' "$previous_clipboard" | pbcopy
  for ip in ${IPS[@]+"${IPS[@]}"}; do ssh-keygen -R "$ip" >/dev/null 2>&1; done
  if [ -z "${KEEP:-}" ]; then
    container stop "$MAIN" "$NOSFTP" >/dev/null 2>&1
    container rm "$MAIN" "$NOSFTP" >/dev/null 2>&1
  fi
  cp "$REPORT" "$ROOT/build/qa-container/report.md" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

command -v container >/dev/null || { echo "Apple's container CLI is required (brew install container)." >&2; exit 1; }
PUBKEY="$(ls ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub 2>/dev/null | head -1)"
[ -n "$PUBKEY" ] || { echo "No SSH public key in ~/.ssh; create one with ssh-keygen -t ed25519." >&2; exit 1; }
printf '# dotshot new-user setup QA\n\n%s · %s · container %s\n' "$(date '+%Y-%m-%d %H:%M')" "$(sw_vers -productVersion)" "$(container --version | awk '{print $4}')" > "$REPORT"

echo "==> app"
mkdir -p "$(dirname "$APP")"
"$ROOT/scripts/build.sh" --no-launch --adhoc --app "$APP" >/dev/null || exit 1

echo "==> images"
for pair in "$IMAGE:0" "$IMAGE_NOSFTP:1"; do
  container image inspect "${pair%:*}" >/dev/null 2>&1 \
    || container build -q -t "${pair%:*}" --build-arg NO_SFTP="${pair##*:}" -f "$ROOT/scripts/qa/destination/Containerfile" "$ROOT/scripts/qa/destination" >/dev/null || exit 1
done

start() {  # start <name> <image> → prints the container's IPv4 address once sshd answers
  container rm -f "$1" >/dev/null 2>&1
  container run -d --name "$1" "$2" >/dev/null 2>&1 || return 1
  local ip="" _
  for _ in $(seq 1 30); do
    ip="$(container inspect "$1" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin)[0]; n=(d.get("status") or {}).get("networks") or d.get("networks"); print(n[0]["ipv4Address"].split("/")[0])' 2>/dev/null)"
    [ -n "$ip" ] && ssh-keyscan -T 2 "$ip" >/dev/null 2>&1 && { printf '%s' "$ip"; return 0; }
    sleep 1
  done
  return 1
}

echo "==> destinations"
IP="$(start "$MAIN" "$IMAGE")" || { echo "could not start $MAIN" >&2; exit 1; }
IP2="$(start "$NOSFTP" "$IMAGE_NOSFTP")" || { echo "could not start $NOSFTP" >&2; exit 1; }
IPS=("$IP" "$IP2")
ssh-keygen -R "$IP" >/dev/null 2>&1; ssh-keygen -R "$IP2" >/dev/null 2>&1
echo "   main $IP · no-SFTP $IP2"

step "1. A brand-new machine: unknown host key"
run add box "dev@$IP" "$INBOX"
check "add accepts dev@<ip> with ~/inbound" is "$(cat "$WORK/out")" "saved box → dev@$IP:~/inbound"
run check box; status=$?
check "check refuses an unknown host key" is "$status" "1"
check "…and says to compare the fingerprint" has "$(cat "$WORK/err")" "host key: unknown"

step "2. Verify the fingerprint the way the docs say, then trust it"
inside="$(container exec "$MAIN" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
outside="$(ssh-keyscan -T 5 -t ed25519 "$IP" 2>/dev/null | ssh-keygen -lf - | awk '{print $2}')"
check "fingerprint seen from the Mac matches the one on the machine" is "$outside" "$inside"
ssh-keyscan -T 5 -t ed25519 "$IP" 2>/dev/null >> ~/.ssh/known_hosts

step "3. Key not authorized yet"
run check box; status=$?
check "check fails before the key is authorized" is "$status" "1"
check "…and says to authorize this Mac's key" has "$(cat "$WORK/err")" "key: rejected"

step "4. Authorize the key (what ssh-copy-id does), then check"
container exec -i "$MAIN" su dev -c 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' < "$PUBKEY"
run check box; status=$?
check "check passes" is "$status" "0"
check "check reports the absolute folder" is "$(cat "$WORK/out")" "ok box dev@$IP:/home/dev/inbound"
check "check saved the absolute folder" is "$(/bin/bash "$DS" list)" $'box\tdev@'"$IP"$'\t/home/dev/inbound'
check "the folder was created private (700)" is "$(dexec "$MAIN" 'stat -c %a ~/inbound')" "700"

step "5. First delivery"
printf 'hello from setup QA\n' > "$WORK/First Note.txt"
run send box "$WORK/First Note.txt"; status=$?
first="$(pbpaste)"
check "send succeeds" is "$status" "0"
check "clipboard holds an absolute path in the inbound folder" has "$first" "/home/dev/inbound/First-Note-"
check "content arrived intact" is "$(dexec "$MAIN" "cat '$first'")" "hello from setup QA"
check "delivered file is private (600)" is "$(dexec "$MAIN" "stat -c %a '$first'")" "600"
run send box "$WORK/First Note.txt"
check "a second send of the same name doesn't overwrite" bash -c "[ '$(pbpaste)' != '$first' ]"
check "no partial uploads left behind" is "$(dexec "$MAIN" 'ls -A ~/inbound | grep -c part || true')" "0"

step "6. Hostile file names"
hostile="$WORK/bug\$(touch \${HOME}PWNED)\`id\`;x.png"; printf 'x' > "$hostile"
run send box "$hostile"
check "hostile name delivered under a safe name" has "$(pbpaste)" "/home/dev/inbound/bug-touch-HOME-PWNED-id-x-"
check "nothing ran on the destination" is "$(dexec "$MAIN" 'ls ~ ~/inbound | grep -c PWNED$ || true')" "0"

step "7. Folders other accounts can use"
dexec "$MAIN" 'chmod 777 ~/inbound'
run check box; status=$?
check "check refuses a folder others can write to" is "$status" "1"
check "…and says how to fix it" has "$(cat "$WORK/err")" "chmod 700"
dexec "$MAIN" 'chmod 750 ~/inbound'
run check box
check "check passes but warns about a folder others can read" has "$(cat "$WORK/err")" "other accounts can read"
dexec "$MAIN" 'chmod 700 ~/inbound'
run add root-owned "dev@$IP" /srv
run check root-owned; status=$?
check "check refuses a folder the account can't write to" is "$status" "1"

step "8. A server without SFTP"
ssh-keyscan -T 5 -t ed25519 "$IP2" 2>/dev/null >> ~/.ssh/known_hosts
container exec -i "$NOSFTP" su dev -c 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' < "$PUBKEY"
run add plain "dev@$IP2" "$INBOX"
run check plain; status=$?
check "check passes" is "$status" "0"
check "…and notes that SFTP is off" has "$(cat "$WORK/err")" "SFTP is off"
run send plain "$WORK/First Note.txt"; status=$?
check "delivery works over plain ssh" is "$status" "0"
check "…with the content intact" is "$(dexec "$NOSFTP" "cat '$(pbpaste)'")" "hello from setup QA"

step "9. What an agent on the destination does (dotshot-inbox skill)"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=640x360:rate=10 -t 3 -pix_fmt yuv420p "$WORK/recording.mov"
run send box "$WORK/recording.mov"
rec="$(pbpaste)"
check "'ls -t ~/inbound | head -1' finds the newest capture" is "$(dexec "$MAIN" 'ls -t ~/inbound | head -1')" "$(basename "$rec")"
dexec "$MAIN" "mkdir -p /tmp/dotshot-frames && ffmpeg -loglevel error -i '$rec' -vf 'fps=1,scale=1280:-1' /tmp/dotshot-frames/%03d.png"
check "the skill's ffmpeg command extracts frames from a recording" is "$(dexec "$MAIN" 'ls /tmp/dotshot-frames | wc -l | tr -d " "')" "3"

step "10. The destination goes offline"
container stop "$MAIN" >/dev/null
start_time=$(date +%s)
run send box "$WORK/First Note.txt"; status=$?
elapsed=$(( $(date +%s) - start_time ))
check "send fails cleanly" is "$status" "1"
check "…within 15 seconds (took ${elapsed}s)" bash -c "[ $elapsed -le 15 ]"
check "…and the clipboard holds the local path instead" is "$(pbpaste)" "$WORK/First Note.txt"

echo
echo "$PASS/$((PASS + FAIL)) setup QA checks passed · report: build/qa-container/report.md"
printf '\n**Result:** %s/%s checks passed\n' "$PASS" "$((PASS + FAIL))" >> "$REPORT"
[ "$FAIL" -eq 0 ]
