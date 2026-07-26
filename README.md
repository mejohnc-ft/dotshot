# Shot Pill

Shot Pill is a tiny macOS capture HUD that sends screenshots, screen recordings, and dropped files to your other devices over SSH. It is designed for people who work across a small fleet—Macs, Linux machines, a NAS, or anything reachable through normal SSH or Tailscale SSH.

When idle it occupies a 42 px camera nub. Hover to reveal capture controls, destinations, accent colors, and recent captures.

## Highlights

- Region screenshots with offline OCR-based filenames
- Full-display or selected-region recordings
- Multiple named SSH destinations and remote folders
- Global shortcuts: `⌃⌥⌘S` for a screenshot and `⌃⌥⌘V` for recording
- URL actions for Shortcuts, Raycast, BetterTouchTool, and scripts
- Drag files onto the nub to send them
- Native first-run setup, Launch at Login, display/corner placement, and accent selection
- No server, account, API key, analytics, or third-party runtime dependencies

## Requirements

- macOS 13 or newer
- Apple Command Line Tools (`xcode-select --install`)
- SSH key access to each destination
- Optional: Tailscale for private device addressing

## Install from source

```bash
git clone https://github.com/mejohnc-ft/shot-pill.git
cd shot-pill
./scripts/install.sh
```

The installer builds `~/Applications/Shot Pill.app` and opens guided setup:

1. Install and launch confirmation
2. Screen Recording permission
3. SSH destinations and writable remote folders
4. Guided screenshot/recording test
5. Launch at Login approval
6. Accent, target display, corner, and inset
7. Final shortcut/privacy recap

Setup can be reopened from the gear on the expanded pill or with:

```bash
open -b com.johnc.shotpill 'shotpill://settings'
```

## Configure destination devices

SSH keys should work without a password prompt:

```bash
ssh my-device
```

On the destination, choose or create a receiving folder:

```bash
mkdir -p ~/inbound
chmod 700 ~/inbound
```

During setup, enter:

- **Name:** a short label such as `work`, `nas`, or `ai`
- **SSH host / alias:** `user@host`, a Tailscale hostname, or an entry from `~/.ssh/config`
- **Destination folder:** an absolute path or `~/inbound`

The Test button connects in batch mode, creates the folder when needed, and verifies it is writable.

Destination configuration is stored locally at:

```text
~/Library/Application Support/Shot Pill/destinations.tsv
```

It is never included in the repository or app bundle.

## Use

| Action | Shortcut or URL |
| --- | --- |
| Region screenshot | `⌃⌥⌘S` |
| Screen recording picker | `⌃⌥⌘V` |
| Screenshot to current destination | `shotpill://image` |
| Screenshot to a destination | `shotpill://image?dest=work` |
| Recording picker | `shotpill://video?dest=work` |
| Record display 2 directly | `shotpill://video?dest=work&screen=2` |
| Record selected portion | `shotpill://video?dest=work&screen=region` |
| Open settings | `shotpill://settings` |

After a successful transfer, Shot Pill copies the absolute remote path to the clipboard. If transfer fails, it keeps the local file and copies the local path instead.

Local captures and logs live in `~/Shots`.

## Build

```bash
./scripts/build.sh
```

Useful options:

```bash
./scripts/build.sh --no-launch
./scripts/build.sh --adhoc
./scripts/build.sh --app "$PWD/dist/Shot Pill.app" --no-launch
```

The source installer can create a self-signed local code-signing identity. Its purpose is identity stability: macOS Screen Recording approval can survive later local rebuilds. For polished public binary releases, use an Apple Developer ID certificate and notarization instead.

## Privacy and security

Shot Pill can read screen contents only after explicit macOS approval. Captures are saved locally and sent only through the system `scp` command to destinations you configure. It does not collect telemetry or run a receiving service.

Review [SECURITY.md](SECURITY.md) before reporting a sensitive issue.

## Uninstall

```bash
./scripts/uninstall.sh
```

The uninstaller moves the app to Trash and leaves settings and captures in place.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Shot Pill is available under the [MIT License](LICENSE).
