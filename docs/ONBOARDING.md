# Onboarding checklist

This is the complete first-run contract for Shot Pill.

## 1. Install

- Confirm macOS 13 or newer.
- Confirm Apple Command Line Tools are available.
- Build into `~/Applications/Shot Pill.app`.
- Sign every bundled executable with the same identity.

## 2. Launch

- Start the app as a menu-bar accessory.
- Register the `shotpill://` URL scheme.
- Open onboarding automatically until setup is completed.

## 3. Screen Recording permission

- Request macOS Screen Recording access.
- Link directly to Privacy & Security settings.
- Explain that a relaunch may be required.

## 4. SSH destinations

For every destination collect:

- Friendly unique name
- SSH hostname, `user@host`, Tailscale name, or SSH config alias
- Absolute or home-relative receiving folder

Test with non-interactive SSH. Create the folder and verify it is writable. Never store SSH passwords or private keys.

## 5. Test and tutorial

- Run a real region screenshot.
- Confirm the sent notification.
- Confirm the remote path reaches the clipboard.
- Explain recording selection and `⌘⌃Esc` to stop.
- Explain local fallback when transfer fails.

## 6. Launch at Login

- Register the main app with `SMAppService`.
- Surface `requiresApproval`.
- Link to System Settings → General → Login Items.
- Keep this opt-in and reversible.

## 7. Appearance and position

- Accent color
- Target display
- Corner
- Edge inset

## 8. Done

- Recap global shortcuts and automation URLs.
- State where local captures, logs, and destination configuration live.
- State the privacy boundary.
- Keep setup available from the gear and `shotpill://settings`.

## Additional release requirements

The onboarding flow is not the whole distribution story. Public binary releases should also have:

- A unique app icon and version number
- Developer ID signing and Apple notarization
- Checksums for downloadable artifacts
- A privacy/security statement
- Uninstall and reset instructions
- A documented update strategy
- CI compile validation
