#!/bin/bash
# Build the macOS release image: Raven.app on the release engine (scripts/make-app.sh: raven-node,
# raven-tor-helper and RavenNearby.app inside, everything signed ad hoc), packed into a DMG by
# scripts/make-dmg.sh (without --layout, so no Finder window opens).
#
#   scripts/make-release.sh [out-dir]          default: dist
#
# Writes <out-dir>/Raven-<version>.dmg and <out-dir>/Raven-<version>.dmg.sha256. The app is assembled
# in a temporary folder that is removed afterwards, so no release Raven.app is left lying around to be
# opened by accident (a release build runs on the real profile, ~/.raven, and the login Keychain).
# The environment of make-app.sh applies (RAVEN_VERSION, CARGO_TARGET_DIR, RAVEN_HARDENED);
# RAVEN_DEMO and RAVEN_ENGINE=dev are refused here.
#
# Not a Developer ID signature and not notarised: see the README, "Install from the DMG".
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$HERE/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
if [ "${RAVEN_DEMO:-0}" = "1" ] || [ "${RAVEN_ENGINE:-1}" = "dev" ] || [ "${RAVEN_SIGN:-1}" != "1" ]; then
    echo "make-release.sh builds the signed release engine app only (unset RAVEN_DEMO, RAVEN_ENGINE, RAVEN_SIGN)." >&2
    exit 2
fi
unset RAVEN_ENGINE_LIB

WORK="$(mktemp -d "${TMPDIR:-/tmp}/raven-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

"$HERE/scripts/make-app.sh" "$WORK"
APP="$WORK/Raven.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
"$HERE/scripts/make-dmg.sh" "$APP" "$OUT/Raven-$VERSION.dmg"
