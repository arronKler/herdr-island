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

BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)
swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

APP="$ROOT/build/HerdrIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/HerdrIsland" "$APP/Contents/MacOS/HerdrIsland"
if ! lipo -verify_arch arm64 "$APP/Contents/MacOS/HerdrIsland" \
  || ! lipo -verify_arch x86_64 "$APP/Contents/MacOS/HerdrIsland"; then
  echo "packaged app is missing an arm64 or x86_64 slice" >&2
  exit 1
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/HerdrIsland.icns" "$APP/Contents/Resources/HerdrIsland.icns"
cp -R "$BIN_PATH/HerdrIsland_HerdrIsland.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_PATH/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/"

mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_PATH/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/HerdrIsland" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/HerdrIsland"
fi

if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$SPARKLE"
codesign --force --deep --sign - "$APP"

echo "$APP"
