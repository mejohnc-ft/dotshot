# Roadmap

What comes after 1.0, in rough order. Everything here keeps dotshot's promises: no account, no cloud, no
telemetry, and nothing installed on destinations.

## 1.1: history, redaction, and faster sending

**Capture ledger.** An append-only record of every capture and delivery
(`~/Library/Application Support/dotshot/events.tsv`) with a rebuildable SQLite index. Everything below
depends on it. Today, nothing records where a file went, so the recent-captures strip can only copy a file
name.

**Library window** (⌃⌥⌘L, or click RECENT on the pill). Every capture across every destination, with:
- search by name and OCR text;
- filters by destination, date, and type;
- per item: copy the remote path, send to another machine, reveal in Finder, delete locally or from the
  destination.

The recent-captures strip copies the **remote path** instead of the file name.

**Redact before sending** (⌃⌥⌘E, or a "Review before send" toggle on the pill). A small editor opens between
capture and delivery:
- opaque redaction boxes, crop, arrows, boxes, and text;
- dashed boxes pre-drawn over anything that looks like a secret, accepted with one key;
- the file is re-named from the edited image, so redacted text can't leak into the file name.

This keeps secrets off remote disks and out of agent context.

**Path formats per destination.** Plain path, `@path` for Claude Code, or a Markdown image.

**Send the clipboard image** (⌃⌥⌘P), **destination hotkeys** (⌃⌥⌘1–9), and **re-send the last capture** to
another machine.

**Notification actions.** Copy the path again, reveal the file, or send it elsewhere, straight from the
"Sent" notification.

## 1.2: storage and stats

**Local retention.** Off by default. Delete captures after N days or past a size cap, oldest first, to the
Trash. It never removes anything undelivered, pinned, or less than a day old.

**Destination cleanup.** Opt-in per destination. It deletes only files dotshot itself delivered, by exact
name from the ledger, inside that destination's folder: never by pattern, age scan, or glob. It shows a dry
run first.

**Disk usage.** Shown per destination on request.

**Stats**, all local:
- captures per day and week, by destination and type;
- bytes sent;
- delivery time (p50/p90);
- failures by cause.

**Time saved**, shown with its assumption and adjustable: `saved = Σ (B − T)` over delivered captures.
- `B` is the manual baseline. The defaults are 30 s per screenshot, 40 s per recording, and 20 s per file:
  find the file, type an `scp` command, and build the absolute path.
- `T` is the measured delivery time plus 2 s to paste.

**Capture options.** Click highlighting, microphone audio, and window shadows for recordings. Agent-sized
images: cap the long edge for faster sends and fewer tokens.

## Later

- **Read-only gallery for your phone or iPad.** Served from the Mac over your tailnet only, opt-in, off by
  default. It adds a network listener, so the docs and this promise change with it.
- A Mac-side CLI (`dotshot send FILE --to gpu`).
- Shortcuts and Raycast actions.
- Per-project folders on a destination.

## Won't do

- Sync daemons, receivers, or anything else installed on destinations.
- Public sharing links.
- A `dotshot://send?file=…` link. Any web page could use it to send a local file.
