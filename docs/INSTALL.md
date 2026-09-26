# Install dotshot

- [Requirements](#requirements)
- [Download (recommended)](#download-recommended)
- [Opening dotshot the first time](#opening-dotshot-the-first-time)
- [Guided setup](#guided-setup)
- [Build from source](#build-from-source)
- [Migrating from Shot Pill](#migrating-from-shot-pill)
- [Update](#update)
- [Uninstall](#uninstall)

## Requirements

| | |
| --- | --- |
| This Mac | macOS 14 Sonoma or newer, Apple silicon or Intel |
| Destination | Any Mac or Linux machine running an SSH server |
| Authentication | SSH key login from this Mac to the destination, with no password prompt |
| Optional | [Tailscale](https://tailscale.com) for reaching machines on other networks |

## Download (recommended)

1. Go to the [latest release](https://github.com/mejohnc-ft/dotshot/releases/latest).
2. Download `dotshot-<version>.dmg`. If you prefer a ZIP, `dotshot-<version>.zip` holds the same app.
3. Optional: verify the checksum against `SHA256SUMS.txt` from the same release:
   ```bash
   shasum -a 256 ~/Downloads/dotshot-*.dmg
   ```
4. Open the DMG and drag **dotshot** onto **Applications**.
5. Eject the DMG and open **dotshot** from Applications.

dotshot has no Dock icon. It lives as a small camera nub in a screen corner
(bottom right by default) and opens setup on first launch.

## Opening dotshot the first time

Release downloads are signed with a Developer ID
(`Developer ID Application: Jonathan Christensen (5XFXZHC7GQ)`) and notarized by
Apple. macOS asks once whether to open an app downloaded from the internet;
click **Open**. To check a download yourself:

```bash
spctl -a -vv /Applications/dotshot.app     # source=Notarized Developer ID
```

If you run a build that isn't notarized, such as one a fork published or an
older artifact, Gatekeeper blocks it the first time with a message such as
*"Apple could not verify 'dotshot' is free of malware"*. To open it anyway:

  1. Click **Done** in the message. Don't move the app to the Trash.
  2. Open **System Settings → Privacy & Security**.
  3. Scroll to **Security**. Next to *"dotshot" was blocked to protect your Mac*,
     click **Open Anyway** and confirm with your password.
  4. Open dotshot again and click **Open**.

  On macOS 14 you can also Control-click dotshot in Applications, choose
  **Open**, and confirm.

  If you verified the checksum and prefer Terminal, removing the quarantine flag
  does the same thing:

  ```bash
  xattr -dr com.apple.quarantine /Applications/dotshot.app
  ```

## Guided setup

Setup opens automatically until you finish it. To reopen it, click the gear on
the expanded pill or run `open 'dotshot://settings'`.

| Step | What to do |
| --- | --- |
| 1. Why dotshot | A short overview of capture, deliver, and use |
| 2. Permission | Click **Request Permission** and turn on dotshot under **Screen & System Audio Recording**. Quit and reopen dotshot if macOS asks, then click **Check Again**. |
| 3. SSH Access | Turn on SSH on the destination, then create or copy this Mac's public key. See [SSH_SETUP.md](SSH_SETUP.md). |
| 4. Destinations | Add a name, an SSH address, and a folder for each machine, and press **Test** on each one. Test checks the host, the key, and the folder separately and saves the absolute folder path. First-time setup needs at least one passing test. |
| 5. First Capture | Press `⌃⌥⌘S`, drag over an area, wait for **Sent**, and paste the copied path into your agent |
| 6. Launch at Login | Optional. Approve dotshot in **System Settings → General → Login Items** if asked. |
| 7. Appearance | Accent color, display, corner, and edge inset for the nub |
| 8. Done | A recap of shortcuts and automation URLs |

![dotshot setup: connecting destination devices over SSH](images/setup-connect.png)

### What a destination looks like

| Field | Example | Notes |
| --- | --- | --- |
| Name | `work` | One word. Used in the pill menu and in `dotshot://…?dest=work`. |
| SSH address or alias | `dev@mac-studio.local`, `dev@100.64.0.10`, `dev@gpu-box`, `studio` | Anything `ssh` accepts without prompting |
| Folder | `~/inbound`, `/srv/inbound` | Test turns `~/…` into an absolute path |

## Build from source

Requires Apple Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/mejohnc-ft/dotshot.git
cd dotshot
./scripts/install.sh
```

The installer builds `~/Applications/dotshot.app` and launches it. It offers to
create a local, self-signed code-signing identity, so macOS keeps the Screen
Recording approval across rebuilds. Ad-hoc builds may ask for approval again
after each rebuild.

Other build options:

```bash
./scripts/build.sh --no-launch                  # build without launching
./scripts/build.sh --universal --no-launch      # arm64 + x86_64
./scripts/build.sh --app "$PWD/dist/dotshot.app" --adhoc --no-launch
```

## Migrating from Shot Pill

dotshot was previously called **Shot Pill**. The first time dotshot launches, it:

- copies `~/Library/Application Support/Shot Pill/destinations.tsv` into dotshot's folder (only if dotshot has none yet)
- copies preferences: accent, current destination, display, corner, inset, recording source, and setup completion
- quits a running Shot Pill, because both apps would compete for the same shortcuts

Three things don't carry over:

- **Screen Recording permission** belongs to the app's identity, so grant it again for dotshot.
- **Launch at Login:** turn it on again in setup.
- **Automation URLs** now start with `dotshot://` instead of `shotpill://`. Update any Shortcuts, Raycast, or BetterTouchTool actions that use them.

Captures stay in `~/Shots`. To remove the old app afterward, run
`./scripts/uninstall.sh --legacy` from a source checkout, or delete
`Shot Pill.app` and turn it off under **System Settings → General → Login Items**.

## Update

dotshot doesn't check for updates or connect to the internet on its own.

- **DMG install:** download the new release, quit dotshot (hover the nub and click ×), and replace the app in Applications. Your settings and Screen Recording approval are kept.
  If captures come back blank after an update, turn dotshot off and on under
  **Privacy & Security → Screen & System Audio Recording**, or run
  `tccutil reset ScreenCapture com.mejohnc.dotshot` and relaunch.
- **Source install:** `git pull && ./scripts/install.sh`

To get notified about new versions, **Watch → Custom → Releases** on the
[GitHub repository](https://github.com/mejohnc-ft/dotshot).

## Uninstall

1. Quit dotshot: hover the nub and click ×.
2. Move `dotshot.app` to the Trash. macOS removes its Login Item automatically.
3. Optional reset:
   ```bash
   rm -r ~/Library/Application\ Support/dotshot   # destinations
   defaults delete com.mejohnc.dotshot             # preferences
   tccutil reset ScreenCapture com.mejohnc.dotshot # Screen Recording approval
   rm -r ~/Shots                                   # local copies of captures, only if you want them gone
   ```

From a source checkout, `./scripts/uninstall.sh` does steps 1 and 2 and prints
the reset commands.
