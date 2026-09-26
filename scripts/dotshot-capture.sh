#!/bin/bash
# dotshot-capture.sh — capture or send a file, name it, deliver it over SSH, copy the path.
#
#   dotshot-capture.sh image <dest>              interactive region screenshot
#   dotshot-capture.sh video <dest> [display]    display 1, 2, … records that screen; omitted = region UI
#   dotshot-capture.sh send  <dest> <file>       deliver an existing file under a safe, unique name
#
# <dest> is a name from destinations.tsv (name<TAB>ssh-host-or-alias<TAB>remote-folder).
#
# Naming backend (DOTSHOT_NAMER, default local):
#   local          Apple Vision OCR — offline and instant; picks up on-screen UI text, minus secret-like words.
#   claude | codex Use an installed, already-authenticated CLI for semantic names; falls back to OCR.
#                  This uploads the capture to that CLI's model provider.
#
# The app runs this script with a fixed environment (scriptEnvironment in App.swift) because it inherits
# dotshot's Screen Recording permission. Environment for tests: DOTSHOT_CONFIG, DOTSHOT_SHOTS_DIR,
# DOTSHOT_NAMER, DOTSHOT_NAMER_TIMEOUT, DOTSHOT_RESIZE_PRESET, DOTSHOT_SSH_TIMEOUT, DOTSHOT_TEST_BIN.
set -uo pipefail
umask 077

# System tools only from system folders. DOTSHOT_TEST_BIN lets the tests substitute stubs.
export PATH="${DOTSHOT_TEST_BIN:+$DOTSHOT_TEST_BIN:}/usr/bin:/bin:/usr/sbin:/sbin"
RESOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="${DOTSHOT_CONFIG:-$HOME/Library/Application Support/dotshot/destinations.tsv}"
SHOTS="${DOTSHOT_SHOTS_DIR:-$HOME/Shots}"
NAMER="${DOTSHOT_NAMER:-local}"
NAMER_TIMEOUT="${DOTSHOT_NAMER_TIMEOUT:-30}"
RESIZE_PRESET="${DOTSHOT_RESIZE_PRESET:-AVAssetExportPreset1280x720}"
SSH_TIMEOUT="${DOTSHOT_SSH_TIMEOUT:-10}"
LOG="$SHOTS/.dotshot.log"
MODE=""
WORK=""
TS="$(date +%Y%m%d-%H%M%S)"
# Host keys must already be known; a stalled link gives up after ~30 s instead of hanging.
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o "ConnectTimeout=$SSH_TIMEOUT"
          -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
# Reuse one SSH connection for the upload and the rename that follows it.
if [ -d "$HOME/.ssh" ] && [ -z "${DOTSHOT_TEST_BIN:-}" ]; then
  SSH_OPTS+=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/dotshot-%C" -o ControlPersist=60)
fi

prepare_shots() {
  mkdir -p "$SHOTS" && chmod 700 "$SHOTS" 2>/dev/null
  # Keep the log bounded: one previous generation, about 1 MB each.
  if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$LOG" "$LOG.1"
  fi
}

log() { mkdir -p "$SHOTS" && printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${MODE:-?}" "$*" >> "$LOG"; }

# Launched by the app: print a line the app turns into a dotshot notification.
# Standalone: values are passed as AppleScript arguments, never interpolated into source.
notify() {
  if [ "${DOTSHOT_NOTIFY_STDOUT:-}" = 1 ]; then
    local title="${1//[$'\t\n']/ }" body="${2//[$'\t\n']/ }"
    printf 'dotshot-notify\t%s\t%s\n' "$title" "$body"
    return
  fi
  osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "$1" "$2" >/dev/null 2>&1
}

setclip() {
  printf '%s' "$1" | pbcopy 2>/dev/null \
    || osascript -e 'on run argv' -e 'set the clipboard to (item 1 of argv)' -e 'end run' "$1" >/dev/null 2>&1
}

helper() {
  local name="$1"; shift
  [ -x "$RESOURCE_DIR/$name" ] || return 127
  "$RESOURCE_DIR/$name" "$@"
}

# Quotes a value for a POSIX shell on the destination. (sed, because ${var//…} replacement quoting
# differs between the system bash 3.2 and bash 5.2+.)
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

valid_host() { [[ "$1" != -* && "$1" =~ ^[A-Za-z0-9._%+@-]+$ ]]; }

# shellcheck disable=SC2088  # a literal ~ is expanded later on the destination
valid_folder() {
  local dir="${1%/}"
  [[ "$1" = /* || "$1" = "~/"* ]] || return 1
  [ -n "$dir" ] && [ "$dir" != "~" ] || return 1
  [[ "/$1/" != */../* && "$1" != *[[:cntrl:]]* ]]
}

# Sets DEST_NAME, DEST_SSH, DEST_DIR for a destination name. Rejects unsafe or malformed rows.
# Tolerates CRLF line endings and spaces around fields, like the app.
resolve_destination() {
  local wanted="$1" line
  DEST_NAME=""; DEST_SSH=""; DEST_DIR=""
  [ -n "$wanted" ] && [ -f "$CONFIG_FILE" ] || return 1
  line="$(awk -F '\t' -v wanted="$wanted" '
    /^#/ { next }
    { sub(/\r$/, ""); for (i = 1; i <= 3; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    NF >= 3 && $1 == wanted { printf "%s\t%s\t%s\n", $1, $2, $3; exit }' "$CONFIG_FILE")"
  [ -n "$line" ] || return 1
  IFS=$'\t' read -r DEST_NAME DEST_SSH DEST_DIR <<< "$line"
  [ -n "$DEST_NAME" ] && valid_host "$DEST_SSH" && valid_folder "$DEST_DIR" || return 1
  DEST_DIR="${DEST_DIR%/}"
}

# Agents need absolute paths; expand a leading ~ using the destination's $HOME.
# shellcheck disable=SC2088
absolute_remote_dir() {
  case "$DEST_DIR" in
    "~/"*)
      local remote_home
      remote_home="$(ssh "${SSH_OPTS[@]}" -- "$DEST_SSH" 'printf %s "$HOME"' 2>>"$LOG")" || return 1
      [[ "$remote_home" = /* ]] || return 1
      printf '%s%s' "${remote_home%/}" "${DEST_DIR#\~}" ;;
    *) printf '%s' "$DEST_DIR" ;;
  esac
}

# ASCII letters from accented text (café → cafe); characters with no ASCII form are dropped.
# macOS iconv mangles these (naïve → na"i'e), so decompose with the system perl instead.
to_ascii() {
  if [ -x /usr/bin/perl ]; then
    /usr/bin/perl -CSD -MUnicode::Normalize -pe '$_ = NFD($_); s/\p{Mn}//g; s/[^\x00-\x7f]//g' 2>/dev/null
  else
    LC_ALL=C tr -cd '\000-\177'
  fi
}

# Secret-looking words never become part of a name: e-mail addresses, known token prefixes, long
# random-looking strings, mixed-case words with digits, and whatever follows "password", "token", etc.
scrub_secrets() {
  awk '{
    out = ""; skip = 0
    for (i = 1; i <= NF; i++) {
      w = $i; lw = tolower(w)
      if (skip) { skip = 0; continue }
      if (lw ~ /^(password|passwd|passcode|pwd|secret|token|apikey|api_key|api-key|pin|otp)[:=]?$/) { skip = 1; out = out " " w; continue }
      if (w ~ /@/) continue
      if (w ~ /^(sk-|sk_|pk_|rk_|ghp_|gho_|ghs_|ghu_|github_pat_|glpat-|xox[abprs]-|AKIA|ASIA|AIza|eyJ|ya29\.|-----BEGIN)/) continue
      if (length(w) >= 20 && w ~ /[A-Za-z]/ && w ~ /[0-9]/) continue
      if (length(w) >= 8 && w ~ /[a-z]/ && w ~ /[A-Z]/ && w ~ /[0-9]/) continue
      out = out " " w
    }
    print substr(out, 2)
  }'
}

slugify() {
  printf '%s\n' "$1" | head -1 \
    | to_ascii \
    | scrub_secrets \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9\n' ' ' \
    | tr -s ' ' | sed 's/^ *//; s/ *$//' \
    | cut -d' ' -f1-6 | tr ' ' '-' \
    | cut -c1-48 | sed 's/-*$//'
}

# File names become part of a path an agent reads and a shell may see: ASCII letters, digits, '.', '_'
# and '-' only, no leading '.' or '-', a bounded length, and a timestamp so nothing is ever overwritten.
safe_filename() {
  local base stem ext=""
  base="$(basename -- "$1" | to_ascii)"
  if [[ "$base" == ?*.* ]]; then
    ext="${base##*.}"; stem="${base%.*}"
    ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-10)"
  else
    stem="$base"
  fi
  stem="$(printf '%s' "$stem" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-' | cut -c1-100 | sed 's/^[-.]*//; s/[-.]*$//')"
  [ -n "$stem" ] || stem="file"
  printf '%s-%s%s' "$stem" "$TS" "${ext:+.$ext}"
}

# Runs a command with a hard timeout, writing stdout to a file. Returns the command's status.
run_with_timeout() {
  local out="$1" seconds="$2"; shift 2
  "$@" >"$out" 2>/dev/null </dev/null &
  local pid=$! status
  ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local killer=$!
  wait "$pid" 2>/dev/null; status=$?
  pkill -P "$killer" 2>/dev/null; kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  return "$status"
}

# An installed agent CLI for DOTSHOT_NAMER, looked up in fixed locations only.
find_cli() {
  local dir
  for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/.claude/local" "$HOME/.npm-global/bin"; do
    [ -x "$dir/$1" ] && { printf '%s' "$dir/$1"; return 0; }
  done
  return 1
}

# Prints salient text for an image; always falls back to offline OCR.
describe_image() {
  local img="$1" text="" out="$WORK/name.txt" cli
  local prompt='Reply with ONLY a short kebab-case filename slug: max 5 words, lowercase, letters/digits/hyphens only, no extension, no quotes, no explanation. Do not include secrets, credentials, or personal data.'
  case "$NAMER" in
    claude)
      if cli="$(find_cli claude)"; then
        (cd "$WORK" && run_with_timeout "$out" "$NAMER_TIMEOUT" "$cli" -p --allowedTools Read "Read the image at $img and $prompt")
        text="$(grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -1)"
      fi ;;
    codex)
      if cli="$(find_cli codex)"; then
        (cd "$WORK" && run_with_timeout /dev/null "$NAMER_TIMEOUT" \
          sh -c 'printf "%s" "$1" | "$2" exec --skip-git-repo-check -o "$3" -i "$4"' _ "$prompt" "$cli" "$out" "$img")
        text="$(grep -v '^[[:space:]]*$' "$out" 2>/dev/null | tail -1)"
      fi ;;
  esac
  [ -n "$text" ] || text="$(helper ocr-slug "$img" 2>/dev/null)"
  printf '%s' "$text"
}

# Moves $1 into ~/Shots as $2 without replacing anything already there; prints the final path.
claim_local() {
  local src="$1" name="$2" stem ext n=1 dest
  stem="${name%.*}"; ext="${name##*.}"; [ "$stem" = "$name" ] && ext=""
  dest="$SHOTS/$name"
  while ! (set -o noclobber; : > "$dest") 2>/dev/null; do
    n=$((n + 1)); dest="$SHOTS/$stem-$n${ext:+.$ext}"
  done
  mv -f "$src" "$dest" && printf '%s' "$dest"
}

fail_delivery() {
  local file="$1" why="$2"
  setclip "$file"
  notify "Saved locally — send to $DEST_NAME failed" "$file (local path copied). $why Details: $LOG"
  log "send FAILED ($why); kept local copy at $file"
  return 1
}

# Copies $1 to the destination as $2 (a safe name) and puts the absolute remote path on the clipboard.
# The upload goes to a hidden temporary name and is renamed on the destination, so an interrupted
# transfer never leaves a partial file under the real name and an existing file is never replaced.
deliver() {
  local file="$1" name="$2" remote_dir part final err="$WORK/scp.err" finalize
  if ! remote_dir="$(absolute_remote_dir)"; then
    fail_delivery "$file" "Could not reach $DEST_SSH."
    return 1
  fi
  part=".$name.$RANDOM$RANDOM.part"
  log "sending '$file' → $DEST_SSH:$remote_dir/$name"
  if ! scp -q "${SSH_OPTS[@]}" -- "$file" "$DEST_SSH:$remote_dir/$part" 2>"$err"; then
    cat "$err" >> "$LOG"
    # No SFTP subsystem on the destination: stream the file through ssh instead (never `scp -O`,
    # whose legacy protocol lets the remote shell expand the path).
    if grep -qiE 'subsystem request failed|connection closed' "$err" \
      && ssh "${SSH_OPTS[@]}" -- "$DEST_SSH" "sh -c $(q "cat > $(q "$remote_dir/$part")")" < "$file" 2>>"$LOG"; then
      log "delivered over ssh (no SFTP on the destination)"
    else
      fail_delivery "$file" "The transfer failed."
      return 1
    fi
  fi
  # Make it private and rename it into place, adding -2, -3, … if the name is taken (or is a symlink).
  local stem="${name%.*}" ext="${name##*.}"; [ "$stem" = "$name" ] && ext=""
  finalize="cd $(q "$remote_dir") || exit 1
    f=$(q "$name"); n=1
    while [ -e \"\$f\" ] || [ -L \"\$f\" ]; do n=\$((n + 1)); f=$(q "$stem")-\$n$(q "${ext:+.$ext}"); done
    chmod 600 $(q "$part") && mv -- $(q "$part") \"\$f\" && printf %s \"\$f\""
  if ! final="$(ssh "${SSH_OPTS[@]}" -- "$DEST_SSH" "sh -c $(q "$finalize")" 2>>"$LOG")" || [ -z "$final" ]; then
    fail_delivery "$file" "The file could not be put in place."
    return 1
  fi
  local remote_path="$remote_dir/$final"
  setclip "$remote_path"
  notify "Sent to $DEST_NAME" "$remote_path (path copied)"
  log "delivered; clipboard=$remote_path"
}

capture_image() {
  RAW="$WORK/raw.png"
  screencapture -i -o -r "$RAW" 2>>"$LOG"   # interactive region; Esc cancels
  [ -s "$RAW" ] || { log "image cancelled"; return 1; }
  SRC="$RAW"; EXT="png"; NAME_SOURCE="$RAW"; DEFAULT_LABEL="shot"
}

# Keeps a recording in ~/Shots without sending it.
keep_recording() {
  local kept
  kept="$(claim_local "$SRC" "rec-$TS.${EXT:-mov}")" || return 1
  notify "Recording kept, not sent" "$kept"
  log "recording kept locally at $kept"
}

capture_video() {
  local display="${1:-}" marker location newest choice
  RAW="$WORK/raw.mov"
  # Region recordings can ignore the file argument and land in the screenshot folder instead.
  location="$(defaults read com.apple.screencapture location 2>/dev/null)"; location="${location/#\~/$HOME}"
  [ -d "$location" ] || location="$HOME/Desktop"
  marker="$WORK/marker"; : > "$marker"
  if [[ "$display" =~ ^[1-9][0-9]*$ ]]; then
    notify "Recording display $display" "Stop with ⌘⌃Esc."
    screencapture -v -D "$display" "$RAW" 2>>"$LOG"
  else
    notify "Recording a selection" "Drag a region, click Record, then stop with ⌘⌃Esc."
    screencapture -U -J video "$RAW" 2>>"$LOG"
  fi
  if [ ! -s "$RAW" ]; then
    # Only macOS's own "Screen Recording …" files made during this capture, newest first.
    newest="$(find "$location" -maxdepth 1 -name 'Screen Recording*.mov' -newer "$marker" -exec stat -f '%m %N' {} + 2>/dev/null \
      | sort -rn | head -1 | cut -d' ' -f2-)"
    [ -n "$newest" ] && [ -f "$newest" ] || { log "video cancelled"; return 1; }
    log "recording saved by macOS at '$newest'; moving it into dotshot"
    mv -f "$newest" "$RAW" || return 1
  fi
  SRC="$RAW"; EXT="mov"

  choice="$(helper panel "Recording ready" "Send as-is, trim it, or resize it smaller." 0 "Send,Trim,Resize" "$SHOTS" 2>/dev/null | cut -f1)"
  log "post-record choice=${choice:-send}"
  case "${choice:-send}" in
    cancel)
      keep_recording
      return 1 ;;
    trim)
      if helper trim "$SRC" "$WORK/trimmed.mov" 2>>"$LOG" && [ -s "$WORK/trimmed.mov" ]; then
        log "trimmed"; SRC="$WORK/trimmed.mov"
      else
        log "trim cancelled or failed"
        keep_recording
        return 1
      fi ;;
    resize)
      notify "Resizing recording" "This can take a moment for long recordings."
      if helper avresize "$SRC" "$WORK/small.mov" "$RESIZE_PRESET" 2>>"$LOG" && [ -s "$WORK/small.mov" ] \
        && [ "$(stat -f %z "$WORK/small.mov")" -lt "$(stat -f %z "$SRC")" ]; then
        log "resized to $RESIZE_PRESET"; SRC="$WORK/small.mov"
      else
        log "resize failed or saved nothing; sending the original"
      fi ;;
  esac

  mkdir -p "$WORK/poster"
  run_with_timeout /dev/null 10 qlmanage -t -s 900 -o "$WORK/poster" "$SRC"
  NAME_SOURCE="$WORK/poster/$(basename "$SRC").png"
  DEFAULT_LABEL="rec"
}

send_file() {
  local file="$1"
  if [ -L "$file" ]; then
    log "send: refused symlink '$file'"; notify "Not sent" "Links aren't sent; drop the file itself."; return 1
  elif [ -d "$file" ]; then
    log "send: refused folder '$file'"; notify "Not sent" "Folders aren't supported; zip it first."; return 1
  elif [ ! -f "$file" ]; then
    log "send: no such file '$file'"; notify "Send failed" "File not found."; return 1
  fi
  deliver "$file" "$(safe_filename "$file")"
}

main() {
  MODE="${1:-}"
  local dest="${2:-}"
  case "$MODE" in
    image|video|send) ;;
    *)
      echo "usage: $(basename "$0") image|video|send <destination> [display|file]" >&2
      return 2 ;;
  esac
  prepare_shots
  WORK="$(mktemp -d /tmp/dotshot.XXXXXX)" || return 1
  trap 'rm -rf "$WORK"' EXIT

  if ! resolve_destination "$dest"; then
    notify "dotshot needs setup" "Destination '$dest' is not configured. Open dotshot settings."
    log "destination '$dest' missing or invalid in $CONFIG_FILE"
    return 1
  fi
  log "start dest=$DEST_NAME"

  if [ "$MODE" = "send" ]; then
    send_file "${3:-}"
    return
  fi

  SRC=""; EXT=""; NAME_SOURCE=""; DEFAULT_LABEL=""
  if [ "$MODE" = "image" ]; then
    capture_image || return 0
  else
    capture_video "${3:-}" || return 0
  fi

  local slug="" final
  [ -f "$NAME_SOURCE" ] && slug="$(slugify "$(describe_image "$NAME_SOURCE")")"
  final="$(claim_local "$SRC" "${slug:-$DEFAULT_LABEL}-$TS.$EXT")" || { log "could not move capture into $SHOTS"; return 1; }
  deliver "$final" "$(basename "$final")"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
