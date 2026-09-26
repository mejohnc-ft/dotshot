#!/bin/bash
# Run every automated check: shell syntax, core unit tests, capture-script tests, and (optionally) a real SSH delivery.
#
#   ./scripts/test.sh                         unit + shell tests
#   DOTSHOT_E2E_HOST=user@host ./scripts/test.sh   also deliver a real file over SSH and clean it up
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dotshot-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "==> shell syntax"
for script in "$ROOT"/scripts/*.sh "$ROOT"/Tests/shell/*.sh; do bash -n "$script"; done
if command -v shellcheck >/dev/null; then
  shellcheck -S warning "$ROOT"/scripts/*.sh "$ROOT"/scripts/docs/*.sh
fi

echo "==> core unit tests"
swiftc -target "$(uname -m)-apple-macos14.0" "$ROOT/Sources/dotshot/Core.swift" "$ROOT/Tests/CoreTests/main.swift" -o "$TMP/core-tests"
"$TMP/core-tests"

echo "==> capture script tests"
"$ROOT/Tests/shell/capture_test.sh"

if [ -n "${DOTSHOT_E2E_HOST:-}" ]; then
  echo "==> end-to-end SSH delivery to $DOTSHOT_E2E_HOST"
  "$ROOT/Tests/shell/e2e_delivery.sh"
fi
