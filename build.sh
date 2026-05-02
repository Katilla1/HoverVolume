#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/HoverVolume.app"
MODULE_CACHE="$ROOT/.build/module-cache"
BINARY="$APP/Contents/MacOS/HoverVolume"

mkdir -p "$APP/Contents/MacOS"
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
    "$ROOT/main.swift" \
    -o "$BINARY"

strip -x "$BINARY" || true

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
