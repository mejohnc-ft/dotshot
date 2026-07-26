#!/bin/bash
# shot-to-work.sh — region screenshot/recording → auto-named → sent to work Mac → name on clipboard.
#
#   shot-to-work.sh            # unified: pops an Image/Video chooser + optional name field
#   shot-to-work.sh image      # skip chooser, go straight to a region screenshot
#   shot-to-work.sh video [dest] [display]
#                              # display 1/2/etc records that full screen; omitted = region UI
#
# Chooser: type a name to override auto-naming (blank = auto). Video offers Send/Trim/Resize after recording.
#
# Naming backend (CLASSIFIER env): local (default) | claude | codex
#   local          — Apple Vision OCR, fully offline, instant. Grabs on-screen UI text — ideal for bug shots.
#   claude / codex — drive the already-installed, already-authed CLI (no API key) for semantic names; slower.
#   The CLI path auto-falls-back to OCR on failure/timeout, so naming never hard-depends on external auth.
set -uo pipefail

# Mouse/automation triggers (BTT, Logi, launchd) run with a bare PATH — pin it so
# claude/codex/scp/swift resolve no matter who launches this.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
RESOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:-}"
NAME_OVERRIDE=""
DEST_HOST="${2:-work}"                 # target SSH alias (2nd arg); default work
RECORD_DISPLAY="${3:-}"                # video only: screencapture display number, 1 = main
CONFIG_FILE="${SHOTPILL_CONFIG:-$HOME/Library/Application Support/Shot Pill/destinations.tsv}"
DEST_LIST="$(awk -F '\t' '!/^#/ && NF >= 3 { names = names (names ? "," : "") $1 } END { print names }' "$CONFIG_FILE" 2>/dev/null)"
SHOTS="$HOME/Shots"
CLASSIFIER="${CLASSIFIER:-local}"      # local (Apple Vision OCR, instant/offline) | claude | codex
CLS_TIMEOUT="${CLS_TIMEOUT:-30}"       # seconds before falling back to OCR
RESIZE_PRESET="${RESIZE_PRESET:-AVAssetExportPreset1280x720}"

# Prefer compiled binaries (instant launch); fall back to interpreting the .swift source.
ocr()    { if [ -x "$RESOURCE_DIR/ocr-slug" ]; then "$RESOURCE_DIR/ocr-slug" "$@"; elif [ -x "$HOME/bin/ocr-slug" ]; then "$HOME/bin/ocr-slug" "$@"; else swift "$HOME/bin/ocr-slug.swift" "$@"; fi; }
resize() { if [ -x "$RESOURCE_DIR/avresize" ];  then "$RESOURCE_DIR/avresize" "$@";  elif [ -x "$HOME/bin/avresize" ];  then "$HOME/bin/avresize" "$@";  else swift "$HOME/bin/avresize.swift" "$@";  fi; }
panel()  { if [ -x "$RESOURCE_DIR/panel" ];     then "$RESOURCE_DIR/panel" "$@";     elif [ -x "$HOME/bin/panel" ];     then "$HOME/bin/panel" "$@";     else swift "$HOME/bin/panel.swift" "$@";     fi; }
PROMPT='Reply with ONLY a short kebab-case filename slug: max 5 words, lowercase, letters/digits/hyphens only, no extension, no quotes, no explanation.'
mkdir -p "$SHOTS"
TS="$(date +%Y%m%d-%H%M%S)"

LOG="$SHOTS/.shot.log"
log() { printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "${MODE:-?}" "$*" >> "$LOG"; }
notify() { osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1; }
# Robust clipboard write: pbcopy, falling back to osascript (some GUI-spawned contexts need it).
setclip() { printf '%s' "$1" | pbcopy 2>/dev/null || osascript -e "set the clipboard to \"$1\"" >/dev/null 2>&1; }
# Resolve a friendly destination name to its SSH host/alias and remote folder.
resolve_destination() {
  local line
  line="$(awk -F '\t' -v wanted="$DEST_HOST" '!/^#/ && $1 == wanted { print; exit }' "$CONFIG_FILE" 2>/dev/null)"
  [ -n "$line" ] || return 1
  IFS=$'\t' read -r DEST_NAME DEST_SSH DEST_DIR <<< "$line"
  [ -n "$DEST_NAME" ] && [ -n "$DEST_SSH" ] && [ -n "$DEST_DIR" ] || return 1
  [[ "$DEST_SSH" != -* && "$DEST_SSH" != *[$' \t\r\n']* ]] || return 1
  [[ "$DEST_DIR" = "~" || "$DEST_DIR" = "~/"* || "$DEST_DIR" = /* ]] || return 1
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9\n' ' ' \
    | tr -s ' ' | sed 's/^ *//; s/ *$//' \
    | cut -d' ' -f1-6 | tr ' ' '-' \
    | cut -c1-48 | sed 's/-*$//'
}

# run "$@" with stdout to <file>, hard-killed after <timeout> seconds
run_to() {
  local out="$1" t="$2"; shift 2
  "$@" >"$out" 2>/dev/null &
  local pid=$!
  ( sleep "$t"; kill -TERM "$pid" 2>/dev/null ) & local killer=$!
  wait "$pid" 2>/dev/null
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
}

# classify <image.png> -> prints salient text (empty on failure)
classify() {
  local img="$1" text="" tmp="/tmp/shot-cls-$$"
  case "$CLASSIFIER" in
    claude)
      run_to "$tmp" "$CLS_TIMEOUT" claude -p "Read the image at $img and $PROMPT"
      text="$(grep -v '^[[:space:]]*$' "$tmp" 2>/dev/null | tail -1)" ;;
    codex)
      ( printf '%s' "$PROMPT" | codex exec --skip-git-repo-check -o "$tmp" -i "$img" >/dev/null 2>&1 ) &
      local pid=$!
      ( sleep "$CLS_TIMEOUT"; kill -TERM "$pid" 2>/dev/null ) & local killer=$!
      wait "$pid" 2>/dev/null; kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
      text="$(grep -v '^[[:space:]]*$' "$tmp" 2>/dev/null | tail -1)" ;;
  esac
  rm -f "$tmp"
  # universal offline fallback (also covers CLASSIFIER=local)
  [ -z "$text" ] && text="$(ocr "$img" 2>/dev/null)"
  echo "$text"
}

# ── Unified chooser (only when no explicit mode arg) ─────────────────────────
if [ -z "$MODE" ]; then
  resp="$(panel "Shot → Work" "Type a name to override auto-naming, or leave blank." 1 "Image,Video" "$SHOTS" "$DEST_LIST" 2>/dev/null)"
  MODE="$(printf '%s' "$resp" | cut -f1)"        # panel already lowercases the button
  NAME_OVERRIDE="$(printf '%s' "$resp" | cut -f2)"
  d="$(printf '%s' "$resp" | cut -f3)"; [ -n "$d" ] && DEST_HOST="$d"
fi
[ "$MODE" = "cancel" ] && exit 0
if ! resolve_destination; then
  notify "Shot Pill needs setup" "Destination '$DEST_HOST' is not configured."
  log "destination '$DEST_HOST' missing from $CONFIG_FILE"
  exit 1
fi
log "=== start mode=$MODE dest=$DEST_HOST override='$NAME_OVERRIDE' ==="

# Drag-drop: ship an existing file (args: send <dest> <file>) — no capture, keep original name.
if [ "$MODE" = "send" ]; then
  FILE="${3:-}"
  [ -f "$FILE" ] || { log "send: no such file '$FILE'"; exit 1; }
  NAME="$(basename "$FILE")"
  REMOTE_ABS="$DEST_DIR/$NAME"
  log "send '$FILE' → $DEST_SSH:$REMOTE_ABS"
  if scp -q "$FILE" "$DEST_SSH:$REMOTE_ABS" 2>>"$LOG"; then
    setclip "$REMOTE_ABS"; notify "Sent → $DEST_HOST" "$NAME  (path copied)"; log "scp OK"
  else
    setclip "$FILE"; notify "Send failed → $DEST_HOST" "$NAME"; log "scp FAILED"
  fi
  exit 0
fi

SRC=""; EXT=""; CLASSIFY_IMG=""; DEFLABEL=""; POSTER=""

case "$MODE" in
  image)
    # Capture to /tmp: screencapture's privileged writer can't write arbitrary folders
    # like ~/Shots, but can always write /tmp. The shell then relocates it.
    RAW="/tmp/shot-raw-$$-$TS.png"
    screencapture -i -o -r "$RAW" 2>>"$LOG"           # interactive region; Esc cancels
    [ -f "$RAW" ] || { log "image cancelled (no file)"; exit 0; }
    SRC="$RAW"; EXT="png"; CLASSIFY_IMG="$RAW"; DEFLABEL="shot"
    ;;

  video)
    RAW="/tmp/shot-raw-$$-$TS.mov"
    # Where interactive recordings land if the file arg isn't honored (screenshot loc, else Desktop).
    SCLOC="$(defaults read com.apple.screencapture location 2>/dev/null)"; SCLOC="${SCLOC/#\~/$HOME}"
    [ -d "$SCLOC" ] || SCLOC="$HOME/Desktop"
    MARK="/tmp/shot-mark-$$"; : > "$MARK"
    if [[ "$RECORD_DISPLAY" =~ ^[1-9][0-9]*$ ]]; then
      notify "Recording display $RECORD_DISPLAY…" "Stop with ⌘⌃Esc."
      screencapture -v -D "$RECORD_DISPLAY" "$RAW" 2>>"$LOG"
    else
      notify "Recording selection…" "Drag a region, click Record, then Stop (⌘⌃Esc)."
      # -J video enters interactive mode; -i is image-only ("video not valid with -i"). -U shows the toolbar.
      screencapture -U -J video "$RAW" 2>>"$LOG"
    fi
    if [ ! -f "$RAW" ]; then                            # file arg not honored → adopt newest recording
      NEW="$(find "$SCLOC" -maxdepth 1 \( -name '*.mov' -o -name '*.mp4' \) -newer "$MARK" 2>/dev/null | head -1)"
      rm -f "$MARK"
      [ -n "$NEW" ] && [ -f "$NEW" ] && RAW="$NEW" || { log "video cancelled (no recording)"; exit 0; }
    else
      rm -f "$MARK"
    fi
    SRC="$RAW"
    # Post-record: send as-is / trim in QuickTime / resize smaller
    choice="$(panel "Recording ready" "Send as-is, trim in QuickTime, or resize smaller." 0 "Send,Trim,Resize" "$SHOTS" 2>/dev/null | cut -f1)"
    log "post-record choice=${choice:-send}"
    case "${choice:-send}" in
      trim)
        open -a "QuickTime Player" "$SRC"
        panel "Trim in QuickTime" "Trim (⌘T → drag the ends → Trim), then Save (⌘S). Click Send when done." 0 "Send" "-" >/dev/null 2>&1
        ;;
      resize)
        SMALL="/tmp/shot-small-$$-$TS.mov"
        if resize "$SRC" "$SMALL" "$RESIZE_PRESET" 2>>"$LOG" && [ -f "$SMALL" ]; then
          log "resized $(basename "$SRC") → $RESIZE_PRESET"; SRC="$SMALL"
        else
          log "resize failed — sending original"
        fi
        ;;
    esac
    # poster frame for naming (no ffmpeg needed)
    POSTER="/tmp/shot-poster-$$-$TS.png"
    qlmanage -t -s 900 -o /tmp "$SRC" >/dev/null 2>&1 && \
      mv "/tmp/$(basename "$SRC").png" "$POSTER" 2>/dev/null
    EXT="mov"; CLASSIFY_IMG="$POSTER"; DEFLABEL="rec"
    ;;

  *)
    notify "shot-to-work" "Unknown mode: $MODE (use image|video)"; exit 1;;
esac

# ── Name: user override wins; else classify the representative image ─────────
if [ -n "$NAME_OVERRIDE" ]; then
  SLUG="$(slugify "$NAME_OVERRIDE")"
else
  SLUG=""; [ -f "$CLASSIFY_IMG" ] && SLUG="$(slugify "$(classify "$CLASSIFY_IMG")")"
fi
[ -n "$POSTER" ] && rm -f "$POSTER"
NAME="${SLUG:-$DEFLABEL}-$TS.$EXT"
FINAL="$SHOTS/$NAME"
mv "$SRC" "$FINAL"

# ── Send to work Mac over tailscale ─────────────────────────────────────────
REMOTE_ABS="$DEST_DIR/$NAME"      # absolute path on the work Mac — what agents should read
log "named: $NAME ; sending to $DEST_SSH:$REMOTE_ABS"
if scp -q "$FINAL" "$DEST_SSH:$REMOTE_ABS" 2>>"$LOG"; then
  setclip "$REMOTE_ABS"
  notify "Sent → $DEST_HOST" "$REMOTE_ABS  (path copied)"
  log "scp OK; clipboard=$REMOTE_ABS"
else
  setclip "$FINAL"
  notify "Saved locally (send failed)" "$FINAL  (local path copied)"
  log "scp FAILED (kept local at $FINAL)"
fi
