#!/bin/bash
# Build the Raven engine for the macOS app: raven-client (the static library the app links),
# raven-node (the background program) and its two helpers, raven-tor-helper (Tor, Arti) and
# raven-nearby-helper (Bluetooth, CoreBluetooth; make-app.sh wraps it in RavenNearby.app).
#
#   scripts/build-engine.sh [release|dev]       default: release
#
#   release  cargo build --locked -p raven-client -p raven-node --release   -> <target>/release/
#   dev      cargo build --locked -p raven-client -p raven-node             -> <target>/debug/
#            (accepts the file-backed test stores; for the engine tests and smoke runs only)
#
# <target> is $CARGO_TARGET_DIR when it is set, else core/node/target. Both profiles build raven-node
# with the features a release needs, `raven-node/tor` (raven-tor-helper) and `raven-node/nearby-radio`
# (raven-nearby-helper); RAVEN_NODE_FEATURES overrides that list ("" builds raven-node alone).
# Whether a carrier is used at run time is still decided by the engine's own gates, not here.
# `--locked`: Cargo.lock is used as it is, nothing is added or updated.
#
# Then link it with RAVEN_ENGINE=1 (release) or RAVEN_ENGINE=dev (see Package.swift), or name the
# library with RAVEN_ENGINE_LIB (make-app.sh does that), e.g.
#   RAVEN_ENGINE=dev swift test
#
# Built for this Mac's architecture only (arm64 on Apple silicon). MACOSX_DEPLOYMENT_TARGET is the
# app's minimum (13.0), so the C code inside (SQLCipher) is not built for the SDK's newer macOS.
# No Rust target or toolchain is installed by this script.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="$(cd "$HERE/core/node" && pwd)"
PROFILE="${1:-release}"
case "$PROFILE" in
    release) CARGO_FLAGS=(--release); DIR="release" ;;
    dev) CARGO_FLAGS=(); DIR="debug" ;;
    *) echo "usage: $0 [release|dev]" >&2; exit 2 ;;
esac
FEATURES="${RAVEN_NODE_FEATURES-raven-node/tor,raven-node/nearby-radio}"
if [ -n "$FEATURES" ]; then CARGO_FLAGS+=(--features "$FEATURES"); fi
TARGET="${CARGO_TARGET_DIR:-$NODE/target}"

command -v cargo >/dev/null || { echo "cargo is missing: install Rust (rustup) to build the engine." >&2; exit 1; }

# A release keeps no home-folder path (and so no user name) in its binaries: the panic messages of
# the dependencies name their source files under $CARGO_HOME (default ~/.cargo), and the bundled C
# code (SQLCipher) keeps __FILE__ paths. Both are rewritten to start with "~" (rustc
# --remap-path-prefix, the C compiler's -ffile-prefix-map; a $CARGO_HOME outside the home folder
# becomes /cargo). On by default for release, off for dev; RAVEN_REMAP_PATHS=0|1 overrides. The flags
# change cargo's fingerprint, so a target folder shared with plain cargo builds is rebuilt in full.
REMAP="${RAVEN_REMAP_PATHS:-}"
if [ -z "$REMAP" ]; then
    if [ "$PROFILE" = release ]; then REMAP=1; else REMAP=0; fi
fi
if [ "$REMAP" = "1" ]; then
    case "$HOME" in
        *[[:space:]]*) echo "HOME has a space: cannot pass it in RUSTFLAGS; use RAVEN_REMAP_PATHS=0" >&2; exit 1 ;;
    esac
    RUST_REMAP="--remap-path-prefix=$HOME=~"
    C_REMAP="-ffile-prefix-map=$HOME=~"
    case "${CARGO_HOME:-$HOME/.cargo}" in
        "$HOME"/*) ;;
        *) RUST_REMAP="$RUST_REMAP --remap-path-prefix=$CARGO_HOME=/cargo"; C_REMAP="$C_REMAP -ffile-prefix-map=$CARGO_HOME=/cargo" ;;
    esac
    export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }$RUST_REMAP"
    export CFLAGS="${CFLAGS:+$CFLAGS }$C_REMAP"
fi

echo "==> Building raven-client and raven-node ($PROFILE, $(uname -m), features: ${FEATURES:-none}, home paths $([ "$REMAP" = 1 ] && echo rewritten || echo kept))"
(cd "$NODE" && MACOSX_DEPLOYMENT_TARGET=13.0 cargo build --locked -p raven-client -p raven-node ${CARGO_FLAGS[@]+"${CARGO_FLAGS[@]}"})

LIB="$TARGET/$DIR/libraven_client.a"
BIN="$TARGET/$DIR/raven-node"
[ -f "$LIB" ] || { echo "missing $LIB" >&2; exit 1; }
[ -x "$BIN" ] || { echo "missing $BIN" >&2; exit 1; }
echo "==> Engine: $LIB"
echo "==> raven-node: $BIN"
case ",$FEATURES," in
    *,raven-node/tor,*)
        [ -x "$TARGET/$DIR/raven-tor-helper" ] || { echo "missing $TARGET/$DIR/raven-tor-helper" >&2; exit 1; }
        echo "==> raven-tor-helper: $TARGET/$DIR/raven-tor-helper" ;;
esac
case ",$FEATURES," in
    *,raven-node/nearby-radio,*)
        [ -x "$TARGET/$DIR/raven-nearby-helper" ] || { echo "missing $TARGET/$DIR/raven-nearby-helper" >&2; exit 1; }
        echo "==> raven-nearby-helper: $TARGET/$DIR/raven-nearby-helper" ;;
esac
