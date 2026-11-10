#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION=""
BUILD_NUMBER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ $# -ge 2 ] || { echo "--version requires a value" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --build)
      [ $# -ge 2 ] || { echo "--build requires a value" >&2; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo "usage: Scripts/make-app.sh [--version <version>] [--build <build>]" >&2
      exit 2
      ;;
  esac
done

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

if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

codesign --force --deep --sign - "$APP"

echo "$APP"
