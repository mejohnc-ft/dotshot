# Changelog

All notable changes to dotshot are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-16

First public release. **Shot Pill is now dotshot.**

### Added
- Signed release downloads: a universal (Apple silicon + Intel) DMG and ZIP with SHA-256 checksums
- Automatic migration from Shot Pill: destinations, preferences, and setup state are imported once, and a running Shot Pill is quit
- `dotshot://setup?step=<name>` opens setup at a specific step
- **Check Again** button for the Screen Recording permission step
- Setup opens automatically when a capture is triggered with no destination configured
- Automated tests for the core logic and the capture script, an optional end-to-end SSH delivery test, and shellcheck in CI
- Release workflow that signs and notarizes when credentials are configured and drafts a GitHub Release
- Install, troubleshooting, QA, and release documentation, plus new screenshots and a demo

### Changed
- New name, bundle identifier (`com.mejohnc.dotshot`), URL scheme (`dotshot://`), and settings folder (`~/Library/Application Support/dotshot`)
- Minimum macOS is now 14 Sonoma, which the app already required
- Transfers never wait for a password prompt; unreachable destinations fail after 10 seconds and keep the local copy
- `~/…` destination folders are resolved to absolute remote paths before the path is copied
- Files sent by drag and drop get whitespace-free names
- Recording **Cancel** keeps the recording locally instead of sending it
- Destination names must be a single word

### Fixed
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
