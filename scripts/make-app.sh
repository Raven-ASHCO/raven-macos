#!/bin/bash
# Build Raven.app from the release binary.
#
#   scripts/make-app.sh [output-dir]          default output: dist
#
# By default the app runs on the Raven engine: scripts/build-engine.sh builds raven-client (linked
# into the app, Package.swift with RAVEN_ENGINE=release) and raven-node, which goes into
# Contents/MacOS/raven-node, where the engine looks for it (next to the app's executable).
#
# Environment:
#   RAVEN_DEMO=1        the clickable demo instead: MockRaven compiled into the release build
#                       (-DRAVEN_MOCK), no engine and no raven-node.
#   RAVEN_ENGINE=dev    link the engine's debug build (cargo's dev profile) and its raven-node. Only
#                       for smoke runs with the file-backed test stores, which a release engine
#                       refuses; never ship it.
#   RAVEN_VERSION=x.y.z CFBundleShortVersionString (default 0.1.0)
#   RAVEN_SIGN=0        skip the ad-hoc signature (by default raven-node and the bundle are signed ad
#                       hoc with `codesign --sign -`, which is not a Developer ID signature and not
#                       notarised)
#   RAVEN_UNIVERSAL=0   build for Apple silicon (arm64) only. The demo is universal by default: arm64
#                       for macOS 13+ plus x86_64 for Intel Macs on macOS 14+, joined with lipo.
#
# The engine app is arm64 only: the engine is built for this Mac's architecture with the Rust targets
# already installed, and the x86_64 Rust target (x86_64-apple-darwin) is not one of them. An Intel
# slice without the engine and raven-node would only show the engine-missing screen, so none is
# built (Finder then says the app does not run on an Intel Mac).
#
# Universal demo build: the Command Line Tools for the macOS 27 SDK ship Swift's back-deployment
# libraries (libswiftCompatibility*.a) for arm64 only, so an x86_64 build for macOS 13 links
# without them ("ignoring file ... missing arch 'x86_64'"). The Intel slice is therefore built for
# macOS 14 (its Swift runtime needs none of them), in its own scratch path, and Info.plist says so
# per architecture (LSMinimumSystemVersionByArchitecture). If the x86_64 build fails, the app is
# arm64 only and the script says so.
#
# Only system tools are used: swift, iconutil, lipo, plutil, PlistBuddy, codesign. The icon is drawn
# by scripts/make-icon.swift (CoreGraphics and ImageIO).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESIGN="$HERE/core/desktop/design"
OUT="${1:-$HERE/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
VERSION="${RAVEN_VERSION:-0.1.0}"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/raven-app.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cd "$HERE"
FLAGS=()
NODE_BIN=""
UNIVERSAL="${RAVEN_UNIVERSAL:-1}"
if [ "${RAVEN_DEMO:-0}" = "1" ]; then
    FLAGS+=(-Xswiftc -DRAVEN_MOCK)
    unset RAVEN_ENGINE RAVEN_ENGINE_LIB
    echo "==> Building the release binary with MockRaven (demo)"
else
    [ "$(uname -m)" = "arm64" ] || { echo "The engine app is built on Apple silicon (arm64) only." >&2; exit 1; }
    case "${RAVEN_ENGINE:-1}" in
        dev) ENGINE_PROFILE=dev; ENGINE_DIR=debug ;;
        *) ENGINE_PROFILE=release; ENGINE_DIR=release ;;
    esac
    "$HERE/scripts/build-engine.sh" "$ENGINE_PROFILE"
    NODE_BIN="$(cd "$HERE/core/node" && pwd)/target/$ENGINE_DIR/raven-node"
    export RAVEN_ENGINE="$ENGINE_PROFILE"    # Package.swift: release or dev
    unset RAVEN_ENGINE_LIB
    UNIVERSAL=0
    echo "==> Building the release binary with the engine ($ENGINE_PROFILE, arm64 only)"
fi
ARM=(--arch arm64)
swift build -c release "${ARM[@]}" --product Raven ${FLAGS[@]+"${FLAGS[@]}"}
BIN_DIR="$(swift build -c release "${ARM[@]}" --show-bin-path)"

# The Intel slice (see "Universal build" above).
INTEL_MIN="14.0"
INTEL=(--scratch-path "$HERE/.build/x86_64" --triple "x86_64-apple-macosx$INTEL_MIN")
INTEL_BIN=""
if [ "$UNIVERSAL" = "1" ]; then
    echo "==> Building the Intel (x86_64, macOS $INTEL_MIN+) slice"
    if swift build -c release "${INTEL[@]}" --product Raven ${FLAGS[@]+"${FLAGS[@]}"}; then
        INTEL_BIN="$(swift build -c release "${INTEL[@]}" --show-bin-path)/Raven"
    else
        echo "==> The x86_64 build failed: the app is for Apple silicon (arm64) only"
    fi
fi

APP="$OUT/Raven.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ -n "$INTEL_BIN" ]; then
    lipo -create "$BIN_DIR/Raven" "$INTEL_BIN" -output "$APP/Contents/MacOS/Raven"
else
    cp "$BIN_DIR/Raven" "$APP/Contents/MacOS/Raven"
fi
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/Raven")"
if [ -n "$NODE_BIN" ]; then
    # The engine starts raven-node from next to the app's executable (RAVEN_NODE_BIN overrides it).
    cp "$NODE_BIN" "$APP/Contents/MacOS/raven-node"
    chmod 755 "$APP/Contents/MacOS/raven-node"
    echo "==> raven-node: $(lipo -archs "$APP/Contents/MacOS/raven-node")"
fi
# Strings, tokens, word list and logo (looked up in Contents/Resources by RavenResources).
cp -R "$BIN_DIR/Raven_RavenUI.bundle" "$APP/Contents/Resources/"
# Older SwiftPM (Swift 6.3) makes the resource bundle without Contents/Info.plist (only its
# resources), and codesign then refuses it ("bundle format unrecognized"). Give it the layout and
# the minimal Info.plist that newer SwiftPM writes; the files themselves stay as they are.
RES_BUNDLE="$APP/Contents/Resources/Raven_RavenUI.bundle"
if [ ! -f "$RES_BUNDLE/Contents/Info.plist" ]; then
    if [ ! -d "$RES_BUNDLE/Contents" ]; then
        mkdir "$RES_BUNDLE/Contents.tmp"
        find "$RES_BUNDLE" -mindepth 1 -maxdepth 1 ! -name Contents.tmp -exec mv {} "$RES_BUNDLE/Contents.tmp/" \;
        mv "$RES_BUNDLE/Contents.tmp" "$RES_BUNDLE/Contents"
    fi
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.github.raven-ashco.Raven.resources" \
        -c "Add :CFBundleName string Raven_RavenUI" \
        -c "Add :CFBundlePackageType string BNDL" \
        -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
        -c "Add :CFBundleDevelopmentRegion string en" \
        "$RES_BUNDLE/Contents/Info.plist" >/dev/null
    echo "==> Resource bundle had no Contents/Info.plist: added the minimal one"
fi

# The app icon: the Raven mark on a light tile that follows the macOS icon grid (make-icon.swift).
ICON_KEY=""
ICONSET="$WORK/Raven.iconset"
if swift "$HERE/scripts/make-icon.swift" "$DESIGN/assets/raven-mark-1024.png" "$DESIGN/tokens.json" "$ICONSET" \
    && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Raven.icns"; then
    ICON_KEY="Raven"
    echo "==> Icon drawn from raven-mark-1024.png and tokens.json"
else
    echo "==> Could not draw the icon: the app has the generic icon"
fi

# The Local Network prompt text comes from strings.en.json (setup.receive.body).
plutil -convert xml1 -o "$WORK/strings.plist" "$DESIGN/strings.en.json"
LOCAL_NETWORK="$(/usr/libexec/PlistBuddy -c "Print :setup.receive.body" "$WORK/strings.plist")"
APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :app.name" "$WORK/strings.plist")"

PLIST="$APP/Contents/Info.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Raven</string>
    <key>CFBundleIdentifier</key><string>io.github.raven-ashco.Raven</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.social-networking</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST
plutil -insert CFBundleName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$PLIST"
plutil -insert NSLocalNetworkUsageDescription -string "$LOCAL_NETWORK" "$PLIST"
if [ -n "$ICON_KEY" ]; then plutil -insert CFBundleIconFile -string "$ICON_KEY" "$PLIST"; fi
if [ -n "$INTEL_BIN" ]; then
    # Finder then explains "needs macOS 14" on an Intel Mac with macOS 13 instead of failing to launch.
    plutil -insert LSMinimumSystemVersionByArchitecture -dictionary "$PLIST"
    plutil -insert LSMinimumSystemVersionByArchitecture.arm64 -string "13.0" "$PLIST"
    plutil -insert LSMinimumSystemVersionByArchitecture.x86_64 -string "$INTEL_MIN" "$PLIST"
fi
plutil -lint "$PLIST" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ "${RAVEN_SIGN:-1}" = "1" ] && command -v codesign >/dev/null; then
    codesign --force --sign - --timestamp=none "$APP/Contents/Resources/Raven_RavenUI.bundle"
    if [ -n "$NODE_BIN" ]; then
        codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/raven-node"
    fi
    codesign --force --sign - --timestamp=none "$APP"
    codesign --verify --strict "$APP"
    echo "==> Signed ad hoc (not a Developer ID signature, not notarised)"
fi

echo "==> Done: $APP"
