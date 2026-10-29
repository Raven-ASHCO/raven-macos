#!/bin/bash
# Build Raven.app from the release binary.
#
#   scripts/make-app.sh [output-dir]          default output: dist
#
# By default the app runs on the Raven engine: scripts/build-engine.sh builds raven-client (linked
# into the app through RAVEN_ENGINE_LIB, see Package.swift), raven-node and its two helpers. The
# bundle carries all of them:
#
#   Raven.app/Contents/MacOS/Raven                       the app (SwiftUI, with the engine linked in)
#   Raven.app/Contents/Helpers/raven-node                the background node the app starts
#   Raven.app/Contents/Helpers/raven-tor-helper          Tor (Arti), started by raven-node
#   Raven.app/Contents/Helpers/RavenNearby.app           Bluetooth (CoreBluetooth), started by raven-node
#   Raven.app/Contents/Resources/                        icon and the resource bundle (texts, word list)
#
# The app points the engine at Contents/Helpers/raven-node at start (BundledNode.swift sets
# RAVEN_NODE_BIN unless it is set already); raven-node finds raven-tor-helper and RavenNearby.app next to
# itself. RavenNearby.app is its own app bundle (Info.plist from core/node/crates/raven-node/macos/, with
# NSBluetoothAlwaysUsageDescription): raven-node starts it as its own responsible process, so macOS asks
# for Bluetooth for "RavenNearby", not for Raven.
#
# Environment:
#   RAVEN_DEMO=1        the clickable demo instead: MockRaven compiled into the release build
#                       (-DRAVEN_MOCK), no engine and no helpers.
#   RAVEN_ENGINE=dev    link the engine's debug build (cargo's dev profile) and its raven-node and
#                       helpers (Swift build in .build/engine-dev). Only for smoke runs with the
#                       file-backed test stores, which a release engine refuses; never ship it.
#   RAVEN_VERSION=x.y.z CFBundleShortVersionString of the app and of RavenNearby.app (default: the
#                       version of core/node/Cargo.toml's workspace, else 0.1.0)
#   CARGO_TARGET_DIR    where cargo builds the engine (default core/node/target)
#   RAVEN_SIGN=0        skip the ad-hoc signatures (by default every piece of code is signed ad hoc
#                       with `codesign --sign -`, inside out: the resource bundle, RavenNearby.app,
#                       raven-tor-helper, raven-node, then the app; this is not a Developer ID
#                       signature and not notarised)
#   RAVEN_HARDENED=0    sign without the hardened runtime (on by default for the app and the helpers;
#                       none of them needs an entitlement)
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
NODE_DIR="$HERE/core/node"
OUT="${1:-$HERE/dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
CORE_VERSION="$(sed -n '/^\[workspace\.package\]/,/^\[/s/^version *= *"\([^"]*\)".*/\1/p' "$NODE_DIR/Cargo.toml" 2>/dev/null | head -n 1)"
VERSION="${RAVEN_VERSION:-${CORE_VERSION:-0.1.0}}"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
MIN_MACOS="13.0"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/raven-app.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cd "$HERE"
FLAGS=()
ENGINE_OUT=""
SCRATCH=()
UNIVERSAL="${RAVEN_UNIVERSAL:-1}"
if [ "${RAVEN_DEMO:-0}" = "1" ]; then
    FLAGS+=(-Xswiftc -DRAVEN_MOCK)
    unset RAVEN_ENGINE RAVEN_ENGINE_LIB
    echo "==> Building the release binary with MockRaven (demo)"
else
    [ "$(uname -m)" = "arm64" ] || { echo "The engine app is built on Apple silicon (arm64) only." >&2; exit 1; }
    case "${RAVEN_ENGINE:-1}" in
        dev) ENGINE_PROFILE=dev; ENGINE_DIR=debug; SCRATCH=(--scratch-path "$HERE/.build/engine-dev") ;;
        *) ENGINE_PROFILE=release; ENGINE_DIR=release ;;
    esac
    "$HERE/scripts/build-engine.sh" "$ENGINE_PROFILE"
    TARGET="${CARGO_TARGET_DIR:-$NODE_DIR/target}"
    case "$TARGET" in /*) ;; *) TARGET="$NODE_DIR/$TARGET" ;; esac   # cargo runs in core/node
    ENGINE_OUT="$TARGET/$ENGINE_DIR"
    for f in raven-node raven-tor-helper raven-nearby-helper; do
        [ -x "$ENGINE_OUT/$f" ] || { echo "missing $ENGINE_OUT/$f: the engine was built without it" >&2; exit 1; }
    done
    export RAVEN_ENGINE="$ENGINE_PROFILE"    # Package.swift: release or dev
    export RAVEN_ENGINE_LIB="$ENGINE_OUT/libraven_client.a"
    UNIVERSAL=0
    echo "==> Building the release binary with the engine ($ENGINE_PROFILE, arm64 only)"
fi
ARM=(--arch arm64 ${SCRATCH[@]+"${SCRATCH[@]}"})
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
HELPERS="$APP/Contents/Helpers"
NEARBY="$HELPERS/RavenNearby.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ -n "$INTEL_BIN" ]; then
    lipo -create "$BIN_DIR/Raven" "$INTEL_BIN" -output "$APP/Contents/MacOS/Raven"
else
    cp "$BIN_DIR/Raven" "$APP/Contents/MacOS/Raven"
fi
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/Raven")"
if [ -n "$ENGINE_OUT" ]; then
    # raven-node and the Tor helper (plain programs), next to each other: raven-node starts
    # raven-tor-helper from its own folder.
    mkdir -p "$HELPERS"
    cp "$ENGINE_OUT/raven-node" "$HELPERS/raven-node"
    cp "$ENGINE_OUT/raven-tor-helper" "$HELPERS/raven-tor-helper"
    chmod 755 "$HELPERS/raven-node" "$HELPERS/raven-tor-helper"
    # RavenNearby.app, also next to raven-node: the core's Info.plist (bundle id org.raven.nearby,
    # NSBluetoothAlwaysUsageDescription), with this release's version and minimum macOS.
    NEARBY_PLIST="$NODE_DIR/crates/raven-node/macos/RavenNearby.app/Contents/Info.plist"
    plutil -lint "$NEARBY_PLIST" >/dev/null
    mkdir -p "$NEARBY/Contents/MacOS"
    cp "$NEARBY_PLIST" "$NEARBY/Contents/Info.plist"
    cp "$ENGINE_OUT/raven-nearby-helper" "$NEARBY/Contents/MacOS/raven-nearby-helper"
    chmod 755 "$NEARBY/Contents/MacOS/raven-nearby-helper"
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$NEARBY/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NEARBY/Contents/Info.plist"
    plutil -replace LSMinimumSystemVersion -string "$MIN_MACOS" "$NEARBY/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Print :NSBluetoothAlwaysUsageDescription" "$NEARBY/Contents/Info.plist" >/dev/null \
        || { echo "RavenNearby.app has no NSBluetoothAlwaysUsageDescription" >&2; exit 1; }
    printf 'APPL????' > "$NEARBY/Contents/PkgInfo"
    for f in "$HELPERS/raven-node" "$HELPERS/raven-tor-helper" "$NEARBY/Contents/MacOS/raven-nearby-helper"; do
        echo "==> $(basename "$f"): $(lipo -archs "$f")"
    done
fi
# A release ships no home-folder path (build-engine.sh rewrites them in the engine's binaries).
if [ -n "$ENGINE_OUT" ] && [ "$ENGINE_PROFILE" = release ] && [ "${RAVEN_REMAP_PATHS:-1}" = "1" ]; then
    for f in "$APP/Contents/MacOS/Raven" "$HELPERS/raven-node" "$HELPERS/raven-tor-helper" \
        "$NEARBY/Contents/MacOS/raven-nearby-helper"; do
        n="$(strings -a "$f" | grep -cF "$HOME/" || true)"
        [ "$n" = "0" ] || { echo "$f names the home folder in $n places: rebuild the engine" >&2; exit 1; }
    done
    echo "==> No home-folder paths in the binaries"
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
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (C) 2026 ASHCO. GNU AGPL v3.0.</string>
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
    plutil -insert LSMinimumSystemVersionByArchitecture.arm64 -string "$MIN_MACOS" "$PLIST"
    plutil -insert LSMinimumSystemVersionByArchitecture.x86_64 -string "$INTEL_MIN" "$PLIST"
fi
plutil -lint "$PLIST" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ "${RAVEN_SIGN:-1}" = "1" ] && command -v codesign >/dev/null; then
    # Inside out: nested code first, the app last (its signature seals what is inside it).
    SIGN=(codesign --force --sign - --timestamp=none)
    CODE=("${SIGN[@]}")
    if [ "${RAVEN_HARDENED:-1}" = "1" ]; then CODE+=(--options runtime); fi
    # The app loads only system libraries by absolute path (nothing through @rpath: the bundle has no
    # Frameworks folder), so the rpath the Swift driver adds to the toolchain's own folder (Command
    # Line Tools or Xcode) is removed: nothing in the bundle points at the build machine.
    MAIN="$APP/Contents/MacOS/Raven"
    if otool -L "$MAIN" | tail -n +2 | grep -q "@rpath/"; then
        echo "Raven loads a library through @rpath, which the bundle does not carry:" >&2
        otool -L "$MAIN" | grep "@rpath/" >&2
        exit 1
    fi
    otool -l "$MAIN" | awk '/LC_RPATH/ { r = 1 } r && / path / { print $2; r = 0 }' | sort -u | while read -r rp; do
        case "$rp" in
            /Library/Developer/*|/Applications/Xcode*) install_name_tool -delete_rpath "$rp" "$MAIN" 2>/dev/null ;;
        esac
    done
    "${SIGN[@]}" "$RES_BUNDLE"
    if [ -n "$ENGINE_OUT" ]; then
        "${CODE[@]}" --identifier org.raven.nearby "$NEARBY"
        "${CODE[@]}" --identifier io.github.raven-ashco.Raven.tor-helper "$HELPERS/raven-tor-helper"
        "${CODE[@]}" --identifier io.github.raven-ashco.Raven.node "$HELPERS/raven-node"
    fi
    "${CODE[@]}" "$APP"
    codesign --verify --deep --strict "$APP"
    echo "==> Signed ad hoc$([ "${RAVEN_HARDENED:-1}" = "1" ] && echo ", hardened runtime") (not a Developer ID signature, not notarised)"
fi

echo "==> Done: $APP ($VERSION, build $BUILD_NUMBER)"
