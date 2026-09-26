---
name: dotshot-setup
description: Set up dotshot on this Mac so screenshots, recordings, and files can be sent to the user's other machines (DGX Spark, ROCm or GPU boxes, Mac VMs, NAS, CI) for coding agents there. Use when the user asks to install or configure dotshot, add or fix a dotshot destination, or "make screenshots reach my agent on <machine>".
---

# Set up dotshot

dotshot captures on this Mac, sends the file over SSH to a folder on another machine, and copies the
absolute remote path. You configure it with the command-line script inside the app. The user only has to
grant Screen Recording permission, which no agent can do for them.

```bash
DS=/Applications/dotshot.app/Contents/Resources/dotshot-capture.sh
"$DS" list                              # configured destinations: name, host, folder
"$DS" add <name> <host> <folder>        # validate and save (replaces a destination with the same name)
"$DS" check <name>                      # host, key, private folder, SFTP; saves the absolute folder
"$DS" send <name> <file>                # deliver a file and copy its remote path
```

## Steps

1. **Is dotshot installed?** Check for `/Applications/dotshot.app`. If it's missing, ask before installing.
   With permission: `brew install --cask mejohnc-ft/tap/dotshot` if the tap exists, otherwise download the
   latest DMG from https://github.com/mejohnc-ft/dotshot/releases/latest. Confirm with
   `spctl -a -vv /Applications/dotshot.app` that it's notarized.
2. **Which machines?** Ask the user which machines their agents run on. Offer candidates from `Host`
   entries in `~/.ssh/config` and, if Tailscale is installed, from `tailscale status`. Pick a short
   one-word name for each (`spark`, `rocm`, `mac`, `nas`).
3. **Can this Mac reach each one without a password?** For each host, run
   `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8 <host> true`.
   - `Host key verification failed`: the host has never been connected to. **Don't** turn off host-key
     checking or edit `known_hosts` yourself. Ask the user to run `ssh <host>` once in Terminal and compare the
     fingerprint with the one shown on the machine itself.
   - `Permission denied`: this Mac's key isn't authorized there. Ask the user to run `ssh-copy-id <host>`,
     which needs that machine's password once. Don't copy private keys anywhere.
   - Timeouts: the machine is off or not on the tailnet. Say so and move on.
4. **Add and check each destination.** Use a dedicated folder, never the home folder itself:
   ```bash
   "$DS" add spark spark '~/inbound'
   "$DS" check spark      # prints "ok spark spark:/home/<user>/inbound" and saves that absolute path
   ```
   `check` creates the folder private to the account (mode 700). It refuses folders other accounts can
   write to, and warns if others can read one. Relay any warning to the user.
5. **Send a real test file** to each destination, then clean up:
   ```bash
   printf 'dotshot setup test\n' > /tmp/dotshot-test.txt
   "$DS" send spark /tmp/dotshot-test.txt && pbpaste      # the absolute remote path
   ssh spark "cat '$(pbpaste)' && rm -f '$(pbpaste)'"
   ```
6. **Hand over to the user.** Tell them:
   - Open dotshot and grant **Screen Recording** in the first setup step. You can't do this for them.
   - Press **⌃⌥⌘S** for a screenshot and **⌃⌥⌘V** for a recording. Switch machines from the pill, or drop
     any file on the corner nub.
   - Optional: install the `dotshot-inbox` skill on each destination (see below), so agents there can find
     "my last screenshot" without a pasted path.

## Destination-side skill

With the user's permission, copy `dotshot-inbox` to each machine where an agent runs:
- Claude Code: `~/.claude/skills/dotshot-inbox/SKILL.md`
- Codex or Pi: the same instructions as a section in that machine's `AGENTS.md`

It's at https://github.com/mejohnc-ft/dotshot/tree/main/skills/dotshot-inbox.

## Don't

- Don't disable `StrictHostKeyChecking`, accept unknown host keys, or add `-o` options to the destinations file.
- Don't use a home folder, `/`, `/tmp`, or any folder other accounts share as a destination.
- Don't turn on AI naming (`dotshot.namer`) unless the user asks. It uploads each capture to a model provider.
