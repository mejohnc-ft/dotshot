# QA

Run before every release on the exact artifact you plan to publish
(`build/release/<version>/dotshot-<version>.dmg`). Record the results at the
bottom of this file.

## Automated

```bash
./scripts/test.sh                                # shellcheck, core unit tests, capture-script tests
DOTSHOT_E2E_HOST=you@host ./scripts/test.sh      # plus a real SSH delivery
./scripts/release.sh                             # runs the tests, builds and verifies the DMG/ZIP
```

| Suite | Covers |
| --- | --- |
| `Tests/CoreTests` | destinations.tsv parsing/serialization, host/folder/name validation, `dotshot://` routing, destination fallback, drop grid mapping, shell quoting, path overrides, Shot Pill migration (copy once, never overwrite) |
| `Tests/shell/capture_test.sh` | slug and file-name sanitizing, destination resolution and rejection of unsafe rows, send/image modes, `~` folder resolution, failure fallback to the local path, AppleScript-injection safety, cancelled captures |
| `Tests/shell/e2e_delivery.sh` | real `scp` to a host, absolute remote path on the clipboard, remote content check, cleanup |

## Manual checklist

Use a Mac user account where dotshot has never run, if possible. `DOTSHOT_CONFIG_DIR`
and `DOTSHOT_SHOTS_DIR` isolate settings when testing on your main account.

### Install and first run
- [ ] DMG opens, shows `dotshot.app` and an `Applications` link; drag-install works
- [ ] First open follows the Gatekeeper path in INSTALL.md (notarized: opens directly)
- [ ] App runs on Apple silicon; on an Intel Mac or under Rosetta (`arch -x86_64`), helpers run
- [ ] No Dock icon; nub appears in bottom-right of the main display; setup opens automatically
- [ ] Setup sidebar labels are not truncated; `SETUP · v<version>` matches the release

### Setup
- [ ] Permission: Request Permission opens the system prompt; Check Again reflects the granted state after relaunch
- [ ] SSH Access: Copy Public Key (or key creation command when no key exists) copies the right text
- [ ] Destinations: Test against a reachable host shows **Ready** and rewrites `~/inbound` to an absolute path
- [ ] Test against an unknown host shows **Host not found**; an unauthorized account shows **Key rejected** with the authorization-command link
- [ ] Continue is blocked on first run until one test passes; invalid rows show the validation message
- [ ] Removing a row clears stale test results
- [ ] Launch at Login toggles and reflects **requires approval** when applicable
- [ ] Appearance: accent, display, corner, and inset move the nub immediately
- [ ] Finish closes setup; relaunching does not reopen it

### Capture and delivery
- [ ] `⌃⌥⌘S` region screenshot → notification **Sent to <dest>** → clipboard holds the absolute remote path → file exists remotely
- [ ] Esc during selection cancels silently, sends nothing
- [ ] Pill **Shot** button does the same; destination menu switches destination
- [ ] `⌃⌥⌘V` opens the recording picker with every display plus Selected Portion; recording a display and a region both deliver a `.mov`
- [ ] After recording: Send, Trim (QuickTime), Resize (1280×720), and Cancel (kept locally) behave as described
- [ ] Drag a file with spaces in its name onto the nub → tiles fill the panel → drop on each tile delivers to the matching destination with a `-` separated name
- [ ] With the destination offline: notification **Saved locally — send failed**, local path on clipboard, error in `~/Shots/.dotshot.log`, no hang longer than ~10 s
- [ ] With no destinations configured, a shortcut opens setup instead of failing silently
- [ ] The pill never appears in its own screenshots or recordings

### Automation
- [ ] `open 'dotshot://image?dest=<name>'`, `dotshot://video?dest=<name>&screen=1`, `dotshot://video?screen=region`, `dotshot://settings`, `dotshot://setup?step=appearance`
- [ ] Unknown actions beep and do nothing

### Migration from Shot Pill
- [ ] With Shot Pill configured and running, first dotshot launch quits Shot Pill and imports destinations and preferences (accent, destination, corner, inset, display, onboarding state)
- [ ] Second launch does not re-import; editing dotshot settings is not overwritten

### Displays
- [ ] Disconnecting the pill's display moves the nub to the main display

### Uninstall
- [ ] Quit via × on the pill; `scripts/uninstall.sh` moves the app to the Trash and prints reset commands

## Results

### 1.0.0 (2026-09-16)

Build: `dotshot-1.0.0.dmg`, universal (arm64 + x86_64), minimum macOS 14.0, signed with `Developer ID Application: Jonathan Christensen (5XFXZHC7GQ)` and notarized (2026-09-26, DMG submission `60b5f744-75f7-4826-aab1-0959831a83a3`).
Tested on macOS 26.6.1 (Apple M5 Max), two displays.

| Area | Result |
| --- | --- |
| `./scripts/test.sh` | Pass: shellcheck, 64/64 core checks, 37/37 capture-script checks |
| Real SSH delivery (`DOTSHOT_E2E_HOST=nas`) | Pass: absolute remote path on the clipboard, content verified, cleaned up |
| Release build | Pass: every binary universal (arm64 + x86_64) with `minos 14.0`; `codesign --verify --deep --strict` OK; DMG verifies |
| Signing and notarization | Pass: app, three helpers, and DMG signed with hardened runtime and secure timestamps; app and DMG notarized and stapled; `stapler validate` OK |
| Simulated download | Pass: DMG and installed app with a quarantine flag are accepted by `spctl` as *Notarized Developer ID*; `syspolicy_check distribution` reports the app ready for distribution |
| Hardened runtime smoke test | Pass: app launches and shows the pill, panel opens, OCR naming (arm64 and x86_64) and 720p resize work, no crash reports |
| Bundled helpers | Pass: OCR naming on the sample captures (arm64 and x86_64 under Rosetta); `avresize` 1920×1080 → 1280×720 |
| Launch smoke test (isolated config) | Pass: runs as an accessory app, no crash reports, only system noise in the log |
| Visual review of every window (pill expanded, collapsed, and drop; recording picker; all 8 setup steps) | Pass after fixes: gray pill buttons, truncated sidebar labels, drop-tile layout and mapping, slider tint, picker alignment, callout widths, contrast, pill height |
| Found and fixed in QA | Wrong minimum macOS, host-only architecture, AppleScript injection in notifications, SSH password-prompt hangs, trailing `-` in sent names, notifications shown as Script Editor, off-screen pill after a display change |
| Manual GUI checklist above | **Not yet run.** Needs a person to click through permission, Test, capture, recording, drag and drop, and migration on the release DMG. |
