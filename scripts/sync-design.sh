#!/bin/bash
# Copy the shared design files into the RavenUI resource folder.
# The design folder is the source of truth; the copies are bundled with the app.
# A unit test (DesignSyncTests) fails when the copies drift from the sources.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESIGN="$HERE/core/desktop/design"
WORDS="$DESIGN/raven-security-words-v1.txt"
DEST="$HERE/Sources/RavenUI/Resources"
mkdir -p "$DEST"
cp "$DESIGN/strings.en.json" "$DESIGN/tokens.json" "$DEST/"
cp "$DESIGN/assets/raven-mark-1024.png" "$DESIGN/assets/raven-mark-64.png" "$DEST/"
if [ -f "$WORDS" ]; then cp "$WORDS" "$DEST/"; fi
chmod 644 "$DEST"/*
echo "Design files copied to $DEST"
