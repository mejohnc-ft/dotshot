#!/bin/bash
# dotshot-capture.sh — capture or send a file, name it, deliver it over SSH, copy the path.
#
#   dotshot-capture.sh image <dest>              interactive region screenshot
#   dotshot-capture.sh video <dest> [display]    display 1, 2, … records that screen; omitted = region UI
#   dotshot-capture.sh send  <dest> <file>       deliver an existing file, keeping its name
#
# <dest> is a name from destinations.tsv (name<TAB>ssh-host-or-alias<TAB>remote-folder).
#
# Naming backend (DOTSHOT_NAMER, default local):
#   local          Apple Vision OCR — offline and instant; picks up on-screen UI text.
#   claude | codex Use an installed, already-authenticated CLI for semantic names; falls back to OCR.
#
# Environment for tests and advanced use: DOTSHOT_CONFIG, DOTSHOT_SHOTS_DIR, DOTSHOT_NAMER,
# DOTSHOT_NAMER_TIMEOUT, DOTSHOT_RESIZE_PRESET, DOTSHOT_SSH_TIMEOUT.
set -uo pipefail

# GUI and automation launches get a bare PATH; pin one so scp/claude/codex resolve.
export PATH="${DOTSHOT_TEST_BIN:+$DOTSHOT_TEST_BIN:}$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
RESOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="${DOTSHOT_CONFIG:-$HOME/Library/Application Support/dotshot/destinations.tsv}"
SHOTS="${DOTSHOT_SHOTS_DIR:-$HOME/Shots}"
NAMER="${DOTSHOT_NAMER:-${CLASSIFIER:-local}}"
NAMER_TIMEOUT="${DOTSHOT_NAMER_TIMEOUT:-30}"
RESIZE_PRESET="${DOTSHOT_RESIZE_PRESET:-AVAssetExportPreset1280x720}"
SSH_TIMEOUT="${DOTSHOT_SSH_TIMEOUT:-10}"
LOG="$SHOTS/.dotshot.log"
MODE=""
SSH_OPTS=(-o BatchMode=yes -o "ConnectTimeout=$SSH_TIMEOUT")

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

# Sets DEST_NAME, DEST_SSH, DEST_DIR for a destination name. Rejects unsafe or malformed rows.
resolve_destination() {
  local wanted="$1" line
  DEST_NAME=""; DEST_SSH=""; DEST_DIR=""
  [ -n "$wanted" ] && [ -f "$CONFIG_FILE" ] || return 1
  line="$(awk -F '\t' -v wanted="$wanted" '!/^#/ && NF >= 3 && $1 == wanted { print; exit }' "$CONFIG_FILE")"
  [ -n "$line" ] || return 1
  IFS=$'\t' read -r DEST_NAME DEST_SSH DEST_DIR _ <<< "$line"
  [ -n "$DEST_NAME" ] && [ -n "$DEST_SSH" ] && [ -n "$DEST_DIR" ] || return 1
  [[ "$DEST_SSH" != -* && "$DEST_SSH" != *[$' \t\r\n']* ]] || return 1
  # shellcheck disable=SC2088  # a literal ~ is expanded later on the destination
  [[ "$DEST_DIR" = "~" || "$DEST_DIR" = "~/"* || "$DEST_DIR" = /* ]] || return 1
  DEST_DIR="${DEST_DIR%/}"; [ -n "$DEST_DIR" ] || DEST_DIR="/"
}

# Agents need absolute paths; expand a leading ~ using the destination's $HOME.
absolute_remote_dir() {
  # shellcheck disable=SC2088
  case "$DEST_DIR" in
    "~"|"~/"*)
      local remote_home
      remote_home="$(ssh "${SSH_OPTS[@]}" "$DEST_SSH" 'printf %s "$HOME"' 2>>"$LOG")" || return 1
      [[ "$remote_home" = /* ]] || return 1
      printf '%s%s' "$remote_home" "${DEST_DIR#\~}" ;;
    *) printf '%s' "$DEST_DIR" ;;
  esac
}

slugify() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9\n' ' ' \
    | tr -s ' ' | sed 's/^ *//; s/ *$//' \
    | head -1 \
    | cut -d' ' -f1-6 | tr ' ' '-' \
    | cut -c1-48 | sed 's/-*$//'
}

# File names become part of a path an agent reads; keep them shell- and prompt-friendly.
safe_filename() {
  local name
  name="$(basename -- "$1")"
  name="$(printf '%s' "$name" | tr '\t\r\n' '   ' | sed 's/[[:space:]]\{1,\}/-/g')"
  [ -n "$name" ] && [ "$name" != "." ] && [ "$name" != ".." ] || name="file"
  printf '%s' "$name"
}

# Runs a command with a hard timeout, writing stdout to a file.
run_with_timeout() {
  local out="$1" seconds="$2"; shift 2
  "$@" >"$out" 2>/dev/null &
  local pid=$!
  ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null ) &
  local killer=$!
  wait "$pid" 2>/dev/null
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
}

# Prints salient text for an image; always falls back to offline OCR.
describe_image() {
  local img="$1" text="" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/dotshot-name.XXXXXX")"
  local prompt='Reply with ONLY a short kebab-case filename slug: max 5 words, lowercase, letters/digits/hyphens only, no extension, no quotes, no explanation.'
  case "$NAMER" in
    claude)
      run_with_timeout "$tmp" "$NAMER_TIMEOUT" claude -p "Read the image at $img and $prompt"
      text="$(grep -v '^[[:space:]]*$' "$tmp" 2>/dev/null | tail -1)" ;;
    codex)
      run_with_timeout /dev/null "$NAMER_TIMEOUT" \
        sh -c 'printf "%s" "$1" | codex exec --skip-git-repo-check -o "$2" -i "$3"' _ "$prompt" "$tmp" "$img"
      text="$(grep -v '^[[:space:]]*$' "$tmp" 2>/dev/null | tail -1)" ;;
  esac
  rm -f "$tmp"
  [ -n "$text" ] || text="$(helper ocr-slug "$img" 2>/dev/null)"
  printf '%s' "$text"
}

# Copies $1 to the destination as $2 and puts the absolute remote path on the clipboard.
deliver() {
  local file="$1" name="$2" remote_dir remote_path
  if ! remote_dir="$(absolute_remote_dir)"; then
    remote_dir="$DEST_DIR"
  fi
  remote_path="${remote_dir%/}/$name"
  log "sending '$file' → $DEST_SSH:$remote_path"
  if scp -q "${SSH_OPTS[@]}" -- "$file" "$DEST_SSH:$remote_path" 2>>"$LOG"; then
    setclip "$remote_path"
    notify "Sent to $DEST_NAME" "$remote_path (path copied)"
    log "delivered; clipboard=$remote_path"
    return 0
  fi
  setclip "$file"
  notify "Saved locally — send to $DEST_NAME failed" "$file (local path copied). Details: $LOG"
  log "scp FAILED; kept local copy at $file"
  return 1
}

# Raw captures go to /tmp: the screencapture writer can reliably write there.
capture_image() {
  RAW="$(mktemp /tmp/dotshot-raw.XXXXXX)" && rm -f "$RAW" && RAW="$RAW.png"
  screencapture -i -o -r "$RAW" 2>>"$LOG"   # interactive region; Esc cancels
  [ -s "$RAW" ] || { log "image cancelled"; rm -f "$RAW"; return 1; }
  SRC="$RAW"; EXT="png"; NAME_SOURCE="$RAW"; DEFAULT_LABEL="shot"
}

capture_video() {
  local display="${1:-}" marker location newest choice
  RAW="$(mktemp /tmp/dotshot-raw.XXXXXX)" && rm -f "$RAW" && RAW="$RAW.mov"
  # Interactive recordings can ignore the file argument and land in the screenshot folder instead.
  location="$(defaults read com.apple.screencapture location 2>/dev/null)"; location="${location/#\~/$HOME}"
  [ -d "$location" ] || location="$HOME/Desktop"
  marker="$(mktemp "${TMPDIR:-/tmp}/dotshot-mark.XXXXXX")"
  if [[ "$display" =~ ^[1-9][0-9]*$ ]]; then
    notify "Recording display $display" "Stop with ⌘⌃Esc."
    screencapture -v -D "$display" "$RAW" 2>>"$LOG"
  else
    notify "Recording a selection" "Drag a region, click Record, then stop with ⌘⌃Esc."
    screencapture -U -J video "$RAW" 2>>"$LOG"
  fi
  if [ ! -s "$RAW" ]; then
    newest="$(find "$location" -maxdepth 1 \( -name '*.mov' -o -name '*.mp4' \) -newer "$marker" 2>/dev/null | head -1)"
    rm -f "$marker"
    [ -n "$newest" ] && [ -f "$newest" ] || { log "video cancelled"; return 1; }
    RAW="$newest"
  else
    rm -f "$marker"
  fi
  SRC="$RAW"

  choice="$(helper panel "Recording ready" "Send as-is, trim in QuickTime, or resize smaller." 0 "Send,Trim,Resize" "$SHOTS" 2>/dev/null | cut -f1)"
  log "post-record choice=${choice:-send}"
  case "${choice:-send}" in
    cancel)
      local kept="$SHOTS/rec-$TS.mov"
      mv "$SRC" "$kept" && log "recording kept locally at $kept"
      return 1 ;;
    trim)
      open -a "QuickTime Player" "$SRC"
      helper panel "Trim in QuickTime" "Trim (⌘T, drag the ends, Trim), then save (⌘S). Click Send when done." 0 "Send" "-" >/dev/null 2>&1 ;;
    resize)
      local small
      small="$(mktemp "${TMPDIR:-/tmp}/dotshot-small.XXXXXX")" && rm -f "$small" && small="$small.mov"
      if helper avresize "$SRC" "$small" "$RESIZE_PRESET" 2>>"$LOG" && [ -s "$small" ]; then
        log "resized to $RESIZE_PRESET"; rm -f "$SRC"; SRC="$small"
      else
        log "resize failed; sending original"
      fi ;;
  esac

  POSTER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-poster.XXXXXX")"
  qlmanage -t -s 900 -o "$POSTER_DIR" "$SRC" >/dev/null 2>&1
  NAME_SOURCE="$POSTER_DIR/$(basename "$SRC").png"
  EXT="mov"; DEFAULT_LABEL="rec"
}

main() {
  MODE="${1:-}"
  local dest="${2:-}"
  mkdir -p "$SHOTS"
  TS="$(date +%Y%m%d-%H%M%S)"

  case "$MODE" in
    image|video|send) ;;
    *)
      echo "usage: $(basename "$0") image|video|send <destination> [display|file]" >&2
      return 2 ;;
  esac

  if ! resolve_destination "$dest"; then
    notify "dotshot needs setup" "Destination '$dest' is not configured. Open dotshot settings."
    log "destination '$dest' missing or invalid in $CONFIG_FILE"
    return 1
  fi
  log "start dest=$DEST_NAME"

  if [ "$MODE" = "send" ]; then
    local file="${3:-}"
    [ -f "$file" ] || { log "send: no such file '$file'"; notify "Send failed" "File not found."; return 1; }
    deliver "$file" "$(safe_filename "$file")"
    return
  fi

  SRC=""; EXT=""; NAME_SOURCE=""; DEFAULT_LABEL=""; POSTER_DIR=""
  if [ "$MODE" = "image" ]; then
    capture_image || return 0
  else
    capture_video "${3:-}" || return 0
  fi

  local slug=""
  [ -f "$NAME_SOURCE" ] && slug="$(slugify "$(describe_image "$NAME_SOURCE")")"
  [ -n "$POSTER_DIR" ] && rm -rf "$POSTER_DIR"
  local name="${slug:-$DEFAULT_LABEL}-$TS.$EXT"
  local final="$SHOTS/$name"
  mv "$SRC" "$final" || { log "could not move capture into $SHOTS"; return 1; }
  deliver "$final" "$name"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
