#!/bin/bash
# Build the Raven engine for the macOS app: raven-client (the static library the app links) and
# raven-node (the background program make-app.sh puts next to the app's executable).
#
#   scripts/build-engine.sh [release|dev]       default: release
#
#   release  cargo build -p raven-client -p raven-node --release   -> core/node/target/release/
#   dev      cargo build -p raven-client -p raven-node             -> core/node/target/debug/
#            (accepts the file-backed test stores; for the engine tests and smoke runs only)
#
# Then link it with RAVEN_ENGINE=1 (release) or RAVEN_ENGINE=dev (see Package.swift), e.g.
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

command -v cargo >/dev/null || { echo "cargo is missing: install Rust (rustup) to build the engine." >&2; exit 1; }

echo "==> Building raven-client and raven-node ($PROFILE, $(uname -m))"
(cd "$NODE" && MACOSX_DEPLOYMENT_TARGET=13.0 cargo build -p raven-client -p raven-node ${CARGO_FLAGS[@]+"${CARGO_FLAGS[@]}"})

LIB="$NODE/target/$DIR/libraven_client.a"
BIN="$NODE/target/$DIR/raven-node"
[ -f "$LIB" ] || { echo "missing $LIB" >&2; exit 1; }
[ -x "$BIN" ] || { echo "missing $BIN" >&2; exit 1; }
echo "==> Engine: $LIB"
echo "==> raven-node: $BIN"
