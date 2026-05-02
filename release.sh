#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/HoverVolume.app"
DIST="$ROOT/dist"
ZIP="$DIST/HoverVolume-macOS.zip"
SUMS="$DIST/SHA256SUMS.txt"

"$ROOT/build.sh"
mkdir -p "$DIST"
rm -f "$ZIP" "$SUMS"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "$SUMS"

echo "Created $ZIP"
