#!/bin/bash
# Build GoSTL-Swift/GoSTL/Resources/AppIcon.icns from the SVG masters.
#
# The .icns is checked into the repository because the release runner has no
# vector tooling; this script is what regenerates it when the artwork changes.
# Run it after editing gen-appicon.py, and commit the result.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$REPO/GoSTL-Swift/GoSTL/Resources/AppIcon.icns"
STAGE="$(mktemp -d)/AppIcon.iconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert not found. Install it with: brew install librsvg" >&2
    exit 1
fi

python3 "$HERE/gen-appicon.py"
mkdir -p "$STAGE"

# Each entry is "<iconset name> <pixel size> <master>". Which master serves a
# size is a legibility call, not an arbitrary one — see gen-appicon.py.
render() {
    local name="$1" px="$2" master="$3"
    rsvg-convert -w "$px" -h "$px" "$HERE/$master" -o "$STAGE/$name"
    printf '  %-24s %4s px  %s\n' "$name" "$px" "$master"
}

render icon_16x16.png        16   AppIcon-small.svg
render icon_16x16@2x.png     32   AppIcon-small.svg
render icon_32x32.png        32   AppIcon-small.svg
render icon_32x32@2x.png     64   AppIcon-medium.svg
render icon_128x128.png      128  AppIcon.svg
render icon_128x128@2x.png   256  AppIcon.svg
render icon_256x256.png      256  AppIcon.svg
render icon_256x256@2x.png   512  AppIcon.svg
render icon_512x512.png      512  AppIcon.svg
render icon_512x512@2x.png   1024 AppIcon.svg

iconutil -c icns "$STAGE" -o "$OUT"
rm -rf "$(dirname "$STAGE")"

echo
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
