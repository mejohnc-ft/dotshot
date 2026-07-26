# Contributing

## Development

Requirements:

- macOS 13 or newer
- Apple Command Line Tools

Build and launch:

```bash
./scripts/build.sh
```

Compile without launching:

```bash
./scripts/build.sh --app "$PWD/dist/Shot Pill.app" --no-launch --adhoc
```

## Validation

Before opening a pull request:

```bash
swiftc -typecheck Sources/ShotPill.swift
bash -n scripts/shot-to-work.sh
./scripts/build.sh --app "$PWD/dist/Shot Pill.app" --no-launch --adhoc
codesign --verify --deep --strict "$PWD/dist/Shot Pill.app"
```

Do not commit destination configuration, screenshots, recordings, signing certificates, keys, or notarization credentials.
