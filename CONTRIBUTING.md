# Contributing

## Requirements

- macOS 14 or newer
- Apple Command Line Tools (`xcode-select --install`)
- Optional: `shellcheck` (`brew install shellcheck`)

## Layout

| Path | Contents |
| --- | --- |
| `Sources/dotshot/Core.swift` | UI-free logic: paths, destinations, URL routing, drop grid, Shot Pill migration |
| `Sources/dotshot/App.swift` | Pill, recording picker, and guided setup (SwiftUI/AppKit) |
| `Sources/dotshot/main.swift` | Entry point |
| `Sources/helpers/` | Bundled helper executables: post-recording panel, OCR naming, video resize |
| `scripts/dotshot-capture.sh` | Capture, name, deliver, and copy the path |
| `Tests/` | Core unit tests (dependency-free runner) and capture-script tests with stubbed `ssh`/`scp` |
| `scripts/docs/` | Reproducible screenshots, demo, and site media |
| `site/` | Landing page published to GitHub Pages |

## Build and test

```bash
./scripts/build.sh                                    # build ~/Applications/dotshot.app and launch it
./scripts/test.sh                                     # all automated checks
DOTSHOT_E2E_HOST=you@host ./scripts/test.sh           # also a real SSH delivery (cleans up after itself)
```

Before opening a pull request:

- `./scripts/test.sh` passes
- `./scripts/build.sh --universal --adhoc --no-launch --app "$PWD/dist/dotshot.app"` succeeds
- For UI changes, run the relevant parts of [docs/QA.md](docs/QA.md) and include before/after screenshots. `./scripts/docs/capture-media.sh` produces screenshots with sample data.

Don't commit destination configuration, captures, signing certificates, keys, or notarization credentials.
