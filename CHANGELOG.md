# Changelog

All notable changes to dotshot are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-16

First public release. **Shot Pill is now dotshot.**

### Added
- Signed and notarized release downloads: a universal (Apple silicon + Intel) DMG and ZIP with SHA-256 checksums
- Automatic migration from Shot Pill: destinations, preferences, and setup state are imported once, and a running Shot Pill is quit
- `dotshot://setup?step=<name>` opens setup at a specific step
- **Check Again** button for the Screen Recording permission step
- Setup opens automatically when a capture is triggered with no destination configured
- Automated tests for the core logic and the capture script, an optional end-to-end SSH delivery test, and shellcheck in CI
- Release workflow that signs and notarizes when credentials are configured and drafts a GitHub Release
- Install, troubleshooting, QA, and release documentation, a screen-by-screen walkthrough, new screenshots, a demo loop, and a 80-second intro video

### Security
- The capture script runs with a fixed, minimal environment and system-only `PATH`, so other software can't borrow dotshot's Screen Recording permission through environment variables, `BASH_ENV`, or planted binaries; the released app ignores development overrides
- Links that would start a recording ask for confirmation
- Strict host-key checking on every connection, and keepalives so a stalled transfer ends
- Uploads go to a hidden temporary name and are renamed into place with private permissions (600); existing files and planted symlinks are never overwritten
- Dropped files get safe ASCII names with a timestamp: no shell syntax, leading `-` or `.`, or overlong names; symlinks and folders are refused
- Screenshot names drop secret-looking words (e-mail addresses, API keys, tokens, text after "password")
- `~/Shots` and the temporary capture folder are private to your account; the log rotates
- Setup creates private destination folders, refuses folders other accounts can write to, and warns about ones they can read
- Release signing runs in a protected, approval-gated environment with a non-exportable key; all GitHub Actions are pinned to commit SHAs
- New SECURITY.md: where every copy of a capture lives, and the remaining risks

### Changed
- New name, bundle identifier (`com.mejohnc.dotshot`), URL scheme (`dotshot://`), and settings folder (`~/Library/Application Support/dotshot`)
- Minimum macOS is now 14 Sonoma, which the app already required
- Transfers never wait for a password prompt; unreachable destinations fail after 10 seconds and keep the local copy
- `~/…` destination folders are resolved to absolute remote paths before the path is copied
- Files sent by drag and drop get safe names with a timestamp
- Trim uses a built-in trim window instead of QuickTime
- Drop targets support up to six destinations
- A link to an unknown destination reports it instead of sending to another machine
- One interactive capture at a time; a second shortcut press while one is running is ignored
- Destination folders must be a folder of their own, not your home folder
- Recording **Cancel** keeps the recording locally instead of sending it
- Destination names must be a single word

### Fixed
- Trim sent the untrimmed recording, and cancelling it still sent the recording
- A region recording could pick up, move, and send an unrelated video from the screenshot folder
- A corrupt recording could hang the pipeline in the poster step
- Captures in the same second overwrote each other locally and remotely
- AI naming always waited for its full 30-second timeout
- Destinations without SFTP never received files
- An interrupted transfer left a partial file under the real name
- A `~` folder whose home lookup failed waited twice and copied a non-absolute path
- Resize could produce a larger file
- CRLF line endings or stray spaces in `destinations.tsv` broke delivery
- OCR names mangled accented text
- Builds ran only on the macOS version and CPU architecture of the build machine
- The pill's Shot and Vid buttons appeared gray instead of the accent color
- Drop targets didn't fill the panel and didn't match the tiles with fewer than four destinations
- Notification text built from file names could be interpreted as AppleScript
- Dropped files were sent through a login-shell command string
- Sent file names picked up a trailing `-`
- Setup sidebar labels were truncated; the edge-inset slider ignored the accent color
- Removing a destination row showed test results for the wrong rows
- The pill stayed off-screen after its display was disconnected

## [0.2.0] - 2026-07-26

Shot Pill: value-first onboarding, SSH-friendly destination testing, single-instance launch.

[1.0.0]: https://github.com/mejohnc-ft/dotshot/releases/tag/v1.0.0
[0.2.0]: https://github.com/mejohnc-ft/dotshot/commit/fe51ac6
