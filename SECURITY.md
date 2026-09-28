# Security model and data handling

dotshot holds macOS Screen Recording permission and copies files to other machines over SSH. This page
explains what it trusts, where every copy of a capture goes, and what it does to keep those copies private.

- [What dotshot trusts](#what-dotshot-trusts)
- [Where a capture goes](#where-a-capture-goes)
- [Transport](#transport)
- [Names](#names)
- [Protecting the Screen Recording permission](#protecting-the-screen-recording-permission)
- [Automation links](#automation-links)
- [Risks you should know about](#risks-you-should-know-about)
- [Releases and signing](#releases-and-signing)
- [Reporting a vulnerability](#reporting-a-vulnerability)

## What dotshot trusts

Your Mac user account, your SSH configuration and keys, and the destinations you configure. It does not
trust other apps, web pages, or files you drop on it, and it treats their names and links as hostile.

dotshot makes no network connections of its own: no analytics, telemetry, update checks, or accounts. The
only traffic is SSH/SFTP to destinations you add, and, if you turn on AI naming, whatever that CLI sends
(see [Names](#names)).

## Where a capture goes

| # | Place | What | Who can read it | How long |
| --- | --- | --- | --- | --- |
| 1 | A private temporary folder (`/tmp/dotshot.XXXXXX`, mode 700) | The raw capture while it's named, trimmed, or resized | Your account | Deleted when the capture finishes |
| 2 | `~/Shots` (mode 700, files 600) | The named capture | Your account, and any app running as you | Until you delete it |
| 3 | `~/Shots/.dotshot.log` | Hosts, remote paths, errors | Your account | Rotated at about 1 MB (one previous copy kept) |
| 4 | The destination folder | The file, mode 600 | The destination account, and root on that machine | Until you delete it; dotshot never cleans up remotely |
| 5 | The clipboard | The absolute remote path (not the image) | Clipboard managers; Universal Clipboard may sync it to your other Apple devices | Until overwritten |
| 6 | A macOS notification | The remote path | Notification Center; the lock screen depending on your preview settings | Until cleared |
| 7 | Your coding agent | The image, once the agent opens the path | The agent's model provider, under its data policy; local agent transcripts | Provider policy |

Setup creates destination folders as mode 700, refuses folders owned by another account or writable by
other accounts, and warns when other accounts can read one.

## Transport

- The system `scp` (SFTP protocol) with key authentication only: `BatchMode=yes`, so no password or
  passphrase prompt can hang a capture.
- `StrictHostKeyChecking=yes` on every connection, whatever `~/.ssh/config` says. A destination you have
  never connected to fails until you connect once in Terminal and **compare the host key fingerprint with
  the one on the destination** (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` there).
- Keepalives (`ServerAliveInterval=10`) end a stalled transfer after about 30 seconds.
- Files upload under a hidden temporary name and are renamed into place, so an interrupted transfer never
  leaves a partial file under the real name. An existing file, or a symlink planted under the same name,
  is never overwritten: the new file gets a `-2`, `-3`, … suffix.
- Destinations without the SFTP subsystem receive the file over plain `ssh` instead. dotshot never uses
  legacy `scp -O`, whose protocol lets the remote shell expand file names.
- dotshot never reads or stores private keys or passwords. Setup reads only `~/.ssh/*.pub` so it can offer
  to copy the public key.

## Names

- **Screenshots and recordings** are named from on-screen text by offline OCR, for example
  `train-loss-llama-8b-sft-run-42-20260926-102200.png`. Before a name is used, words that look like secrets are
  removed: e-mail addresses, API-key and token prefixes (`sk-`, `ghp_`, `AKIA`, `xox…`, JWTs, and others),
  long random-looking strings, mixed-case words with digits, and whatever follows a label such as
  "password" or "token". This is a heuristic; for sensitive work, capture a smaller area.
- **Dropped files** are renamed to ASCII letters, digits, `.`, `_`, and `-`, with a timestamp. Names can't
  carry shell syntax (`$()`, backticks, `;`, quotes, globs), start with `-` or `.`, or grow past 100
  characters. Symlinks and folders are refused.
- **AI naming** (`defaults write com.mejohnc.dotshot dotshot.namer claude` or `codex`) is off by default.
  When on, **each capture is uploaded to that CLI's model provider** just to name it. The CLI runs in an
  empty temporary folder with only its Read tool allowed, and its answer is reduced to `[a-z0-9-]`.

## Protecting the Screen Recording permission

Processes that dotshot starts inherit its Screen Recording permission, so dotshot controls exactly what
they run:

- The capture script gets a fixed environment (`HOME`, `USER`, `TMPDIR`, `SSH_AUTH_SOCK`, and a system-only
  `PATH`). Nothing else from dotshot's own environment is passed on, so `BASH_ENV`, `PATH` entries such as
  `~/.local/bin`, or `DOTSHOT_*` overrides planted by relaunching dotshot with `open --env` have no effect.
- bash runs with `--noprofile --norc`.
- The released app ignores the `DOTSHOT_*` development overrides entirely.
- The app and its helpers are signed with the hardened runtime.

## Automation links

`dotshot://` links can come from any app or web page. A link that would **start a recording** asks first
("Start recording display 2?"), unless you tick **Always allow links to start recordings**. Screenshot
links still need you to drag out a region, so they don't ask. A link naming a destination that doesn't
exist is reported and captures nothing, instead of going to a different machine.

## Risks you should know about

- **Prompt injection.** A capture of untrusted content (a web page, an issue, an e-mail) becomes input to
  your agent. Treat it like pasting untrusted text, and don't run agents on auto-approve for work driven by
  captures of untrusted content.
- **Shared machines.** Anyone with root on a destination can read what you send there.
- **Dedicated keys.** For a destination that only receives captures, you can restrict the key in
  `authorized_keys`: `restrict,command="internal-sftp" ssh-ed25519 AAAA…`. dotshot then needs an absolute
  destination folder (Setup saves one after a passing test).
- **Local copies** in `~/Shots` stay until you delete them.

## Releases and signing

- Releases are signed with a Developer ID (`Jonathan Christensen (5XFXZHC7GQ)`) and notarized by Apple.
  Check an install with `spctl -a -vv /Applications/dotshot.app`, which should report
  `source=Notarized Developer ID`.
- Release builds run in GitHub Actions. Tests run in a job with no secrets. Signing and notarization run
  in a protected environment that only `v*` tags can use and that needs the maintainer's approval. The
  signing key is imported as non-exportable and usable only by `codesign`, and is deleted when the job ends.
  Only the final job can write to the repository.
- Every GitHub Action is pinned to a commit SHA, and only GitHub-owned actions may run. Release tags can't
  be moved or deleted.
- `SHA256SUMS.txt` on a release detects a corrupted download; the Developer ID signature and notarization
  are what prove authenticity.

## Supported versions

Security fixes go to the latest release.

## Reporting a vulnerability

Report privately through [GitHub Security Advisories](https://github.com/mejohnc-ft/dotshot/security/advisories/new).
Don't include screenshots, recordings, credentials, SSH configuration, private keys, or private hostnames in a public issue.
