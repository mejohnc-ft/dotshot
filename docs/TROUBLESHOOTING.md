# Troubleshooting

Start with the delivery log, which records every capture, transfer, and SSH error:

```bash
tail -n 40 ~/Shots/.dotshot.log
```

## Setup and permissions

### The screenshot is only the desktop wallpaper, or capture does nothing

dotshot doesn't have Screen Recording permission yet.

1. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
2. Turn on **dotshot**. If it's already on, turn it off and on again.
3. Quit dotshot (hover the nub and click ×) and open it again.

If the permission seems stuck, especially after upgrading from Shot Pill or
rebuilding from source, reset it and grant it again:

```bash
tccutil reset ScreenCapture com.mejohnc.dotshot
```

### macOS says dotshot can't be opened or verified

See [Opening dotshot the first time](INSTALL.md#opening-dotshot-the-first-time).

### Shortcuts don't respond

- Another app may already use `⌃⌥⌘S` or `⌃⌥⌘V`. Global shortcuts go to whichever app registered them first. Quit the other app, then relaunch dotshot.
- Check that only one copy is running: `pgrep -lf dotshot`. If Shot Pill is still installed and set to open at login, remove it (see [Migrating from Shot Pill](INSTALL.md#migrating-from-shot-pill)).

### A shortcut opens setup instead of capturing

No destination is configured yet. Add one and press **Test**.

### I can't find the pill

It sits in the corner and on the display chosen under **Appearance**. If that
display is disconnected, the pill moves to the main display. Run
`open 'dotshot://setup?step=appearance'` to move it.

## Destination tests

| Test result | Meaning and fix |
| --- | --- |
| Host not found | The hostname, IP, or alias doesn't resolve. For Tailscale, confirm both devices are connected and MagicDNS is on. |
| Timed out / Device unreachable | The device is offline, asleep, or on another network. Try `ping`, or check the Tailscale connection. |
| SSH is off | Turn on **Remote Login** (macOS) or start the OpenSSH server (Linux). |
| Key rejected | This Mac's public key isn't authorized for that account. Use **Copy key authorization command** and run it in Terminal once. |
| Identity check needed | You've never connected to this host. Run `ssh you@host` in Terminal once and verify the fingerprint. |
| Host identity changed | The host key doesn't match `known_hosts`. Find out why before removing the old entry. |
| Folder blocked / read-only | Choose a folder the SSH account owns, such as `~/inbound`. |

Every test and transfer runs the same command you can run yourself:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 you@host 'mkdir -p ~/inbound && cd ~/inbound && pwd -P'
```

If that works in Terminal but not in dotshot, check whether your key has a
passphrase that isn't stored in Keychain. dotshot can't answer passphrase
prompts. Add the key to Keychain with:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Then make sure `~/.ssh/config` includes:

```sshconfig
Host *
    UseKeychain yes
    AddKeysToAgent yes
```

## Delivery

### "Saved locally — send failed"

The capture is in `~/Shots`, and its local path is on the clipboard. The log
shows the `scp` error. Common causes are a sleeping destination, an expired
Tailscale login, or a folder that was deleted on the destination.

### The copied path starts with `~`

dotshot turns `~/…` folders into absolute paths by asking the destination for its
`$HOME`. If that lookup fails, it falls back to the path as written. Press
**Test** in setup to save the absolute path permanently.

### File names

Screenshots are named from on-screen text using offline Apple Vision OCR, plus
a timestamp. When no text is found, the name starts with `shot-` or `rec-`.
Files sent by drag and drop keep their names, with spaces replaced by `-`.

## Recordings

- **Stop recording:** `⌘⌃Esc`, or the stop button in the menu bar.
- After recording, choose **Send**, **Trim** (opens QuickTime; save, then click Send), or **Resize** (re-encodes at 1280×720). Cancel keeps the recording in `~/Shots` without sending it.
- Recordings of a selected area can land in your screenshot folder first. dotshot finds them and moves them into `~/Shots`.

## Still stuck?

Open an issue at <https://github.com/mejohnc-ft/dotshot/issues> with your macOS
version, dotshot version (shown in the setup sidebar), and the relevant log
lines. **Remove hostnames, usernames, and paths you consider private.** Never
attach captures that contain sensitive information.
