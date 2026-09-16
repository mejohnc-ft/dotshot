# dotshot

**Capture here. Let your agents use it there.**

dotshot sends screenshots and screen recordings from your Mac straight to the
machine where your coding agent is working, over SSH, and copies the remote path
to your clipboard. Paste that path into Claude Code, Codex, or any terminal
agent.

```text
⌃⌥⌘S → drag over the problem → named, delivered, path copied → paste into your agent
```

![A dotshot capture delivered to a remote machine and pasted into an agent prompt](docs/images/demo.gif)

There's no save dialog, no file naming, no upload, and no hunting for the file
on the other machine. There's also no account, cloud inbox, receiving service,
telemetry, or API key.

[**Download for macOS**](https://github.com/mejohnc-ft/dotshot/releases/latest) · [Install guide](docs/INSTALL.md) · [SSH setup](docs/SSH_SETUP.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## Why

If you code across a laptop, a desktop, a GPU box, a build machine, or a NAS,
your screenshot usually lands on the wrong computer. dotshot turns what you see
into a path the agent can open right away:

```text
Fix the overflow in /Users/dev/inbound/network-settings-proxy-host-20260916-101400.png
```

Files travel over the SSH or Tailscale connection you already have. On the
destination, dotshot needs nothing but a folder the SSH account can write to.

## Features

- **Region screenshots** with offline, on-device OCR naming (`payment-form-test-failed-20260916-101300.png`)
- **Recordings** of a full display or a selected area, with send, trim, or resize afterward
- **Several destinations**, including a Mac or Linux machine reachable by `user@host`, a Tailscale name, or an `~/.ssh/config` alias
- **Global shortcuts:** `⌃⌥⌘S` for a screenshot, `⌃⌥⌘V` for a recording
- **Drag and drop:** drop any file on the camera nub, then onto a destination tile
- **Automation URLs** for Shortcuts, Raycast, BetterTouchTool, and scripts
- **Guided setup** that tests each destination, diagnoses SSH problems, and walks you through a first capture
- **Stays out of the way:** a 42 px camera nub in the corner of the screen you choose, excluded from your own screenshots

<p align="center">
  <img src="docs/images/pill.png" width="720" alt="The expanded dotshot pill with Shot and Vid buttons, accent colors, and recent captures, next to the collapsed camera nub">
</p>

## Install

**Requirements:** macOS 14 Sonoma or newer (Apple silicon or Intel), plus a Mac or
Linux destination you can SSH into with a key.

1. Download `dotshot-<version>.dmg` from the [latest release](https://github.com/mejohnc-ft/dotshot/releases/latest).
2. Open the DMG and drag **dotshot** to **Applications**.
3. Open dotshot. Setup starts automatically.

If macOS says it can't verify the app, see
[Opening dotshot the first time](docs/INSTALL.md#opening-dotshot-the-first-time).
To build from source instead, see [Build from source](docs/INSTALL.md#build-from-source).

**Upgrading from Shot Pill?** dotshot is the new name. The first launch imports
your destinations and preferences and quits the old app. See
[Migrating from Shot Pill](docs/INSTALL.md#migrating-from-shot-pill).

## Set up in five minutes

Setup walks through each step and can be reopened any time from the gear on the
expanded pill.

1. **Allow Screen Recording** when macOS asks, then relaunch dotshot if prompted.
2. **Make sure SSH works** from this Mac to the destination without a password:
   ```bash
   ssh -o BatchMode=yes you@destination true && echo ready
   ```
   If that fails, setup can copy the key authorization command for you. The
   [SSH setup guide](docs/SSH_SETUP.md) covers Remote Login, keys, and Tailscale.
3. **Add a destination** with a short name (`work`), an SSH address
   (`you@mac-studio.local`), and a folder (`~/inbound`). Press **Test**. dotshot
   checks the host, the key, and the folder separately, creates the folder, and
   saves its absolute path.
4. **Take a first capture** with `⌃⌥⌘S`. Wait for the **Sent** notification, then
   paste the path into your agent.

<p align="center">
  <img src="docs/images/setup-destinations.png" width="720" alt="dotshot setup: destinations with a name, SSH address, and folder, each with a Test button">
</p>

## Use

| Action | How |
| --- | --- |
| Screenshot to the current destination | `⌃⌥⌘S`, or hover the nub and click **Shot** |
| Recording | `⌃⌥⌘V`, or **Vid**, then pick a display or **Selected Portion**. Stop with `⌘⌃Esc`. |
| Switch destination | Click the destination name on the expanded pill |
| Send an existing file | Drag it onto the nub, then onto a destination tile |
| Reopen setup | Gear on the expanded pill, or `open dotshot://settings` |

After a successful transfer, the clipboard holds the absolute remote path. If
the transfer fails, dotshot keeps the file, copies its local path, and logs the
error to `~/Shots/.dotshot.log`.

### Automation URLs

| URL | Effect |
| --- | --- |
| `dotshot://image` | Screenshot to the current destination |
| `dotshot://image?dest=work` | Screenshot to `work` |
| `dotshot://video?dest=work` | Recording picker |
| `dotshot://video?dest=work&screen=2` | Record display 2 |
| `dotshot://video?dest=work&screen=region` | Record a selected area |
| `dotshot://settings` | Open destination settings |
| `dotshot://setup?step=appearance` | Open setup at a step (`welcome`, `permissions`, `connect`, `destinations`, `test`, `login`, `appearance`, `done`) |

```bash
open 'dotshot://image?dest=work'
```

## Where things live

| What | Where |
| --- | --- |
| Local copies of captures | `~/Shots` |
| Delivery log | `~/Shots/.dotshot.log` |
| Destinations | `~/Library/Application Support/dotshot/destinations.tsv` |
| Preferences | `defaults read com.mejohnc.dotshot` |

`destinations.tsv` holds one tab-separated row per destination (name, SSH host
or alias, remote folder). You can edit it by hand. See
[`config/destinations.example.tsv`](config/destinations.example.tsv).

## Privacy and security

dotshot can read the screen only after you grant Screen Recording permission.
Captures are saved locally and sent only to destinations you configure, using
the system `scp` with key authentication. Password prompts are disabled and
host-key checking stays on. dotshot has no analytics, no update service, and no
network access of its own. See [SECURITY.md](SECURITY.md).

## Development

```bash
./scripts/build.sh      # build ~/Applications/dotshot.app and launch it
./scripts/test.sh       # unit tests, capture-script tests, shellcheck
./scripts/release.sh    # universal DMG + ZIP + checksums (see docs/RELEASING.md)
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [docs/QA.md](docs/QA.md), and
[docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE)
