#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/HoverVolume.app"
MODULE_CACHE="$ROOT/.build/module-cache"
BINARY="$APP/Contents/MacOS/HoverVolume"
RESOURCES="$APP/Contents/Resources"
ACTOOL_INFO="$ROOT/.build/actool-info.plist"

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$RESOURCES"
mkdir -p "$MODULE_CACHE"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

swiftc \
    -Osize \
    -whole-module-optimization \
    -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    -framework AppKit \
    -framework AudioToolbox \
    -framework CoreAudio \
    "$ROOT/HoverVolumeLogic.swift" \
    "$ROOT/main.swift" \
    -o "$BINARY"

xcrun actool \
    --compile "$RESOURCES" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ACTOOL_INFO" \
    "$ROOT/Assets.xcassets" >/dev/null

strip -x "$BINARY" || true

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
