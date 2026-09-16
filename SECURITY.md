# Security

## Scope

dotshot has Screen Recording access and transfers user-selected files over SSH. Treat both capabilities as sensitive.

## Data handling

- Captures are saved under `~/Shots`; the delivery log is `~/Shots/.dotshot.log`.
- Destination configuration is stored under `~/Library/Application Support/dotshot`.
- Transfers use the system `ssh` and `scp` with your existing SSH configuration and keys, in batch mode (no password or passphrase prompts) with host-key verification left on.
- Destination hosts that look like SSH options (starting with `-`) or contain whitespace are rejected; remote paths are quoted.
- dotshot never reads or stores private keys or passwords. Setup reads only `~/.ssh/*.pub` so it can offer to copy the public key.
- No capture, hostname, or usage event is sent to the maintainers. dotshot has no analytics and no update service.
- Screenshot file names come from on-screen text (offline OCR), so they can include visible details such as email addresses or project names. Rename sensitive captures, or send them by drag and drop, which keeps your own file name.
- Optional AI naming (`DOTSHOT_NAMER=claude|codex`) is off by default. When enabled, it passes the capture to a CLI you have installed and signed in to.

## Destination trust

You're responsible for verifying SSH host keys and for access controls on receiving folders. Anyone who can read the destination folder can read your captures.

## Supported versions

Security fixes go to the latest release.

## Reporting a vulnerability

Report privately through [GitHub Security Advisories](https://github.com/mejohnc-ft/dotshot/security/advisories/new).
Don't include screenshots, recordings, credentials, SSH configuration, private keys, or private hostnames in a public issue.
