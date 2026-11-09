#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

APP="$ROOT/build/HerdrIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/HerdrIsland" "$APP/Contents/MacOS/HerdrIsland"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/HerdrIsland.icns" "$APP/Contents/Resources/HerdrIsland.icns"
cp -R "$BIN_PATH/HerdrIsland_HerdrIsland.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_PATH/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"

echo "$APP"
