#!/bin/bash
# Build and install dotshot from source into ~/Applications, then open guided setup.
# Prefer the signed release download unless you want to build it yourself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HOME/Applications/dotshot.app"
CERT="dotshot Local Signing"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "dotshot requires macOS." >&2
  exit 1
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  echo "dotshot requires macOS 14 Sonoma or newer." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null; then
  echo "Apple Command Line Tools are required."
  echo "Run: xcode-select --install"
  exit 1
fi

mkdir -p "$HOME/Applications"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$CERT\""; then
  if [ -t 0 ]; then
    printf "Create a local signing identity so Screen Recording approval survives rebuilds? [Y/n] "
    read -r answer
  else
    answer="n"
  fi
  case "${answer:-y}" in
    n|N|no|NO) echo "Continuing with ad-hoc signing; rebuilds may require Screen Recording approval again." ;;
    *) "$ROOT/scripts/create-local-signing-identity.sh" ;;
  esac
fi

LEGACY_APP="$HOME/Applications/Shot Pill.app"
if [ -d "$LEGACY_APP" ]; then
  echo "Found Shot Pill.app (dotshot's previous name). dotshot imports its destinations and settings on first launch."
  echo "Remove the old app afterward with: ./scripts/uninstall.sh --legacy"
fi

DOTSHOT_APP_PATH="$APP" "$ROOT/scripts/build.sh"
echo
echo "Installed $APP. Follow the setup window to grant permission and connect a destination."
