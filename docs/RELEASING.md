# Releasing dotshot

## One-time setup: signing and notarization

Public builds should be signed with a **Developer ID Application** certificate
and notarized by Apple. That requires an [Apple Developer Program](https://developer.apple.com/programs/)
membership. Full Xcode is not needed; the Command Line Tools are enough.

1. **Create a certificate signing request and key** (the key never leaves this Mac):
   ```bash
   mkdir -p ~/.dotshot-signing && chmod 700 ~/.dotshot-signing && cd ~/.dotshot-signing
   openssl genrsa -out devid.key 2048 && chmod 600 devid.key
   openssl req -new -key devid.key -out DeveloperID.certSigningRequest -subj "/CN=dotshot Developer ID/C=US"
   ```
2. **Create the certificate** at [developer.apple.com → Certificates → +](https://developer.apple.com/account/resources/certificates/add):
   choose *Developer ID Application* (G2 Sub-CA), upload the `.certSigningRequest`, and download the `.cer`.
3. **Create an App Store Connect API key** at [App Store Connect → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api)
   with the *Developer* role. Download the `.p8` (only possible once) and note the Key ID and Issuer ID.
4. **Install everything** with one command. It checks that the certificate matches the key, installs
   Apple's Developer ID intermediate certificate if needed, imports the identity, stores a `dotshot-notary`
   notarization profile, and with `--github` sets the six repository secrets below:
   ```bash
   ./scripts/setup-signing.sh --cer ~/Downloads/developerID_application.cer --key ~/.dotshot-signing/devid.key \
     --p8 ~/Downloads/AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-id> --github
   ```
   The first signed build may ask whether `codesign` can use the key; choose **Always Allow**.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The identity as a base64 `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` password |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Jane Doe (TEAMID1234)` |
| `NOTARY_API_KEY_P8` | Contents of `AuthKey_XXXX.p8` |
| `NOTARY_API_KEY_ID` | The key ID |
| `NOTARY_API_ISSUER` | The issuer ID |

Without these secrets, the release workflow still works but produces an
**ad-hoc signed** build. Users then need the Gatekeeper steps in
[INSTALL.md](INSTALL.md#opening-dotshot-the-first-time), and the release notes say so.

To sign and notarize locally:

```bash
DOTSHOT_SIGNING_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" \
DOTSHOT_NOTARY_PROFILE=dotshot-notary \
DOTSHOT_REQUIRE_NOTARIZATION=1 \
./scripts/release.sh
```

## Cutting a release

1. Update `CFBundleShortVersionString` (and bump `CFBundleVersion`) in `Resources/Info.plist`.
2. Add a `## [x.y.z] - YYYY-MM-DD` section to `CHANGELOG.md`. The release workflow uses it as the release notes.
3. Run `./scripts/test.sh` and the manual checklist in [QA.md](QA.md) against a build from `./scripts/release.sh`.
4. Merge to `main`, then tag and push:
   ```bash
   git tag -a v1.0.0 -m "dotshot 1.0.0"
   git push origin v1.0.0
   ```
5. The **release** workflow checks that the tag matches `Info.plist`, runs tests, builds a universal app, signs and notarizes it when secrets exist, and creates a **draft** GitHub Release with the DMG, ZIP, and `SHA256SUMS.txt`.
6. Download the draft's DMG on a clean Mac, or at least a different user account, and run the first-run checks in QA.md.
7. Publish the draft.

## Homebrew (optional)

`scripts/release.sh` writes a ready-to-use cask to `build/release/<version>/dotshot.rb`
(the workflow uploads it as a build artifact). To publish it:

1. Create a public repository named `homebrew-tap` under the same account.
2. Commit the cask as `Casks/dotshot.rb`.
3. Users install with `brew install --cask mejohnc-ft/tap/dotshot`.

Update the cask's `version` and `sha256` for each release. Homebrew's own cask
repository requires notarized apps.

## Landing page

`site/` is deployed to GitHub Pages by `.github/workflows/pages.yml` on pushes
to `main` that change `site/**`. Enable Pages once under **Settings → Pages →
Source: GitHub Actions**.

## Refreshing screenshots and the demo

```bash
./scripts/docs/capture-media.sh     # raw window captures from an isolated demo build
./scripts/docs/compose-media.sh     # docs/images/* and site/images/*
./scripts/docs/make-demo.sh         # docs/images/demo.gif and demo.mp4 (README loop)
./scripts/docs/make-intro.sh        # docs/images/intro.mp4, the 80 s intro with soundtrack (Node.js + ffmpeg)
```

`make-intro.sh --stills` renders a frame every two seconds for a quick review.
The intro's scenes live in `scripts/docs/intro.html`; open it in a browser with
`#t=<seconds>` to preview a single moment. Its sound cues sit next to the animations
(`CUES` in `intro.html`); `scripts/docs/soundtrack.mjs` synthesizes the music and UI
sounds from them, so the audio has no third-party license. `make-intro.sh --audio`
re-mixes only the soundtrack in a few seconds.

Your terminal app needs Screen Recording permission, and Google Chrome must be
installed. These scripts never read your own dotshot settings.
