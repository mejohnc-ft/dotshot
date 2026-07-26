#!/bin/bash
# Source install for macOS. Builds into ~/Applications and launches first-run onboarding.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HOME/Applications/Shot Pill.app"
CERT="Shot Pill Local Signing"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Shot Pill requires macOS." >&2
  exit 1
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 13 ]; then
  echo "Shot Pill requires macOS 13 or newer." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null; then
  echo "Apple Command Line Tools are required."
  echo "Run: xcode-select --install"
  exit 1
fi

mkdir -p "$HOME/Applications"

if ! security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$CERT\""; then
  if [ -t 0 ]; then
    printf "Create a stable local signing identity so Screen Recording approval survives rebuilds? [Y/n] "
    read -r answer
  else
    answer="n"
  fi
  case "${answer:-y}" in
    n|N|no|NO)
      echo "Continuing with ad-hoc signing; updates may require Screen Recording approval again." ;;
    *)
      "$ROOT/scripts/create-local-signing-identity.sh" ;;
  esac
fi

SHOTPILL_APP_PATH="$APP" "$ROOT/scripts/build.sh"
echo
echo "Installation complete. Follow the setup window to configure permission, SSH destinations, testing, login, and appearance."
