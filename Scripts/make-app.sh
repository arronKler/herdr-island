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

# A multi-arch `swift build --arch` trips SwiftTerm's build-tool plugin on
# Xcode 16 (swiftlang/swift-package-manager#7442); build each slice instead.
ARM64_TRIPLE="arm64-apple-macosx14.0"
X86_64_TRIPLE="x86_64-apple-macosx14.0"
ARM64_BIN="$(swift build -c release --triple "$ARM64_TRIPLE" --scratch-path .build/arm64 --show-bin-path)"
X86_64_BIN="$(swift build -c release --triple "$X86_64_TRIPLE" --scratch-path .build/x86_64 --show-bin-path)"
swift build -c release --triple "$ARM64_TRIPLE" --scratch-path .build/arm64
swift build -c release --triple "$X86_64_TRIPLE" --scratch-path .build/x86_64

APP="$ROOT/build/HerdrIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create \
  "$ARM64_BIN/HerdrIsland" \
  "$X86_64_BIN/HerdrIsland" \
  -output "$APP/Contents/MacOS/HerdrIsland"
if ! lipo "$APP/Contents/MacOS/HerdrIsland" -verify_arch arm64 \
  || ! lipo "$APP/Contents/MacOS/HerdrIsland" -verify_arch x86_64; then
  echo "packaged app is missing an arm64 or x86_64 slice" >&2
  exit 1
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/HerdrIsland.icns" "$APP/Contents/Resources/HerdrIsland.icns"
cp -R "$ARM64_BIN/HerdrIsland_HerdrIsland.bundle" "$APP/Contents/Resources/"
cp -R "$ARM64_BIN/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/"
# SwiftPM may copy resources as 0444. The owner must be able to remove the
# download quarantine attribute after Archive Utility restores these modes.
chmod -R u+w "$APP/Contents/Resources"

mkdir -p "$APP/Contents/Frameworks"
ditto "$ARM64_BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
