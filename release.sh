#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/HoverVolume.app"
DIST="$ROOT/dist"
ZIP="$DIST/HoverVolume-macOS.zip"
DAMAGE_ROOT="$ROOT/.build/dmg"
DMG="$DIST/HoverVolume-macOS.dmg"
SUMS="$DIST/SHA256SUMS.txt"

"$ROOT/build.sh"
mkdir -p "$DIST"
rm -rf "$DAMAGE_ROOT"
rm -f "$ZIP" "$DMG" "$SUMS"

mkdir -p "$DAMAGE_ROOT"
ditto "$APP" "$DAMAGE_ROOT/HoverVolume.app"
ln -s /Applications "$DAMAGE_ROOT/Applications"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
hdiutil create \
    -volname "HoverVolume" \
    -srcfolder "$DAMAGE_ROOT" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

shasum -a 256 "$ZIP" "$DMG" > "$SUMS"

echo "Created $ZIP"
echo "Created $DMG"
