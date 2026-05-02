#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$ROOT/HoverVolume.app"
APP_TARGET="$HOME/Applications/HoverVolume.app"

"$ROOT/build.sh"
mkdir -p "$HOME/Applications"
ditto "$APP_SOURCE" "$APP_TARGET"
open "$APP_TARGET"

echo "Installed $APP_TARGET"
