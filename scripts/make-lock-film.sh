#!/bin/bash
# The lock scene's films, for review (debug builds only): renders the scene's own frames with
# `RavenSnapshots --lock-film` (ImageRenderer on MockRaven, 30 frames a second; no screen recording,
# no running app) and makes H.264 MP4s (yuv420p, 1200 x 760) with ffmpeg:
#   lock-light.mp4, lock-dark.mp4      Lock's question by day, the sheet closes, the night comes down
#                                      on the locked screen, the raven asleep
#   unlock-light.mp4, unlock-dark.mp4  asleep, then the night rises and the raven wakes and stretches
#                                      until the main window opens
#   lock-scene-all.mp4                 the four (light lock, light unlock, dark lock, dark unlock) with
#                                      0.3 s of black between
# The frame PNGs go to a new temporary folder and are deleted at the end.
#
#     scripts/make-lock-film.sh [output-directory]       (default: .build/lock-film)
#     RAVEN_FILM_TMP=<folder>   where the temporary frame folder is made (default: $TMPDIR)
#     FFMPEG=<path>             the ffmpeg to use (default: ffmpeg on PATH, else /opt/homebrew/bin/ffmpeg)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$HERE/.build/lock-film}"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)}"
mkdir -p "$OUT"
FRAMES="$(mktemp -d "${RAVEN_FILM_TMP:-${TMPDIR:-/tmp}}/raven-lock-film.XXXXXX")"
trap 'rm -rf "${FRAMES:?}"' EXIT

cd "$HERE"
swift run RavenSnapshots --lock-film "$FRAMES"

ENCODE=(-c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p
        -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart)
TO_YUV="scale=out_color_matrix=bt709:out_range=tv,format=yuv420p"
for film in lock-light lock-dark unlock-light unlock-dark; do
    "$FFMPEG" -hide_banner -loglevel error -y -framerate 30 -i "$FRAMES/$film/%05d.png" \
        -vf "format=rgb24,setsar=1,$TO_YUV" "${ENCODE[@]}" "$OUT/$film.mp4"
done
# All four from the frames themselves (one encode), with 0.3 s of black between.
"$FFMPEG" -hide_banner -loglevel error -y \
    -framerate 30 -i "$FRAMES/lock-light/%05d.png" -framerate 30 -i "$FRAMES/unlock-light/%05d.png" \
    -framerate 30 -i "$FRAMES/lock-dark/%05d.png" -framerate 30 -i "$FRAMES/unlock-dark/%05d.png" \
    -f lavfi -i "color=c=black:s=1200x760:r=30:d=0.3" \
    -filter_complex "[4:v]format=rgb24,setsar=1,split=3[g1][g2][g3];\
[0:v]format=rgb24,setsar=1[a];[1:v]format=rgb24,setsar=1[b];[2:v]format=rgb24,setsar=1[c];[3:v]format=rgb24,setsar=1[d];\
[a][g1][b][g2][c][g3][d]concat=n=7:v=1:a=0,$TO_YUV[v]" \
    -map "[v]" "${ENCODE[@]}" "$OUT/lock-scene-all.mp4"
echo "Lock scene films written to $OUT"
