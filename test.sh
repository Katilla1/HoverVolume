#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODULE_CACHE="$ROOT/.build/module-cache"
TEST_BUILD="$ROOT/.build/tests"
TEST_BINARY="$TEST_BUILD/HoverVolumeLogicTests"

mkdir -p "$MODULE_CACHE" "$TEST_BUILD"

swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -Xcc "-fmodules-cache-path=$MODULE_CACHE" \
    "$ROOT/HoverVolumeLogic.swift" \
    "$ROOT/Tests/HoverVolumeLogicTests.swift" \
    -o "$TEST_BINARY"

"$TEST_BINARY"
