#!/bin/bash
# Make an unsigned developer DMG with the "Drag Raven to Applications" layout:
# the volume holds Raven.app and a symlink to /Applications.
#
#   scripts/make-dmg.sh [path/to/Raven.app] [output.dmg] [--layout]
#
# Defaults: dist/Raven.app -> dist/Raven.dmg (next to the app).
#
# --layout also sets the Finder window (background with the arrow and "Drag Raven to Applications",
# icon positions). That needs the image mounted and Finder scripted, so it OPENS A FINDER WINDOW;
# use it on a build machine, not while someone works at the screen. The background picture is the
# `dmg-background.png` rendered by `swift run RavenSnapshots`.
#
# The image is not signed or notarised (see core/docs/SIGNING_NOTARIZATION_CHECKLIST.md for releases).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HERE/dist/Raven.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
DMG="${2:-$(dirname "$APP")/Raven.dmg}"
LAYOUT=0
if [ "${3:-}" = "--layout" ]; then LAYOUT=1; fi
VOLUME="Raven"

[ -d "$APP" ] || { echo "No app at $APP: run scripts/make-app.sh first." >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/raven-dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"

if [ "$LAYOUT" = "0" ]; then
    echo "==> Creating $DMG"
    hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
else
    BACKGROUND="${RAVEN_DMG_BACKGROUND:-$HERE/.build/snapshots/dmg-background.png}"
    if [ ! -f "$BACKGROUND" ]; then
        (cd "$HERE" && swift run RavenSnapshots "$(dirname "$BACKGROUND")" >/dev/null)
    fi
    mkdir -p "$STAGE/.background"
    cp "$BACKGROUND" "$STAGE/.background/background.png"
    RW="$WORK/raven-rw.dmg"
    hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
    MOUNT="$WORK/mount"
    mkdir -p "$MOUNT"
    hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT" "$RW" >/dev/null
    osascript <<OSA
tell application "Finder"
    set theDisk to (POSIX file "$MOUNT" as alias)
    open theDisk
    set theWindow to container window of theDisk
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 800, 520}
    set opts to icon view options of theWindow
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set background picture of opts to file ".background:background.png" of theDisk
    set position of item "Raven.app" of theWindow to {150, 170}
    set position of item "Applications" of theWindow to {450, 170}
    close theWindow
end tell
OSA
    sync
    hdiutil detach "$MOUNT" >/dev/null
    hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
fi

hdiutil verify "$DMG" >/dev/null
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
