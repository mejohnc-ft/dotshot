# Releasing dotshot

## One-time setup: signing and notarization

Public builds should be signed with a **Developer ID Application** certificate
and notarized by Apple. That requires an [Apple Developer Program](https://developer.apple.com/programs/)
membership.

1. Create a *Developer ID Application* certificate (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com).
2. Export it with its private key as a `.p12` file.
3. Create an App Store Connect API key with the *Developer* role (Users and Access → Integrations → App Store Connect API) and download the `.p8`.
4. Add these repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` export password |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Jane Doe (TEAMID1234)` |
| `NOTARY_API_KEY_P8` | Contents of `AuthKey_XXXX.p8` |
| `NOTARY_API_KEY_ID` | The key ID |
| `NOTARY_API_ISSUER` | The issuer ID |

Without these secrets, the release workflow still works but produces an
**ad-hoc signed** build. Users then need the Gatekeeper steps in
[INSTALL.md](INSTALL.md#opening-dotshot-the-first-time), and the release notes say so.

To sign and notarize locally instead:

```bash
xcrun notarytool store-credentials dotshot-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-id>
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
./scripts/docs/make-intro.sh        # docs/images/intro.mp4, the 55 s intro (Node.js + ffmpeg)
```

`make-intro.sh --stills` renders a frame every two seconds for a quick review.
The intro's scenes live in `scripts/docs/intro.html`; open it in a browser with
`#t=<seconds>` to preview a single moment.

Your terminal app needs Screen Recording permission, and Google Chrome must be
installed. These scripts never read your own dotshot settings.
