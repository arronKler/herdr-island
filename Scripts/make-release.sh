#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "usage: Scripts/make-release.sh <version>   (example: 0.1.0)" >&2
  exit 2
}

[ $# -eq 1 ] || usage

VERSION="$1"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid version: $VERSION" >&2
  usage
fi

BUILD_NUMBER="$(git rev-list --count HEAD)"
COMMIT="$(git rev-parse --short HEAD)"
if ! git diff --quiet HEAD --; then
  echo "warning: working tree has uncommitted changes; the release will not match $COMMIT" >&2
fi

OUT="$ROOT/build/release"
APP="$ROOT/build/HerdrIsland.app"
ZIP_NAME="HerdrIsland-$VERSION.zip"
ZIP="$OUT/$ZIP_NAME"

mkdir -p "$OUT"
rm -f "$ZIP" "$ZIP.sha256"

Scripts/make-app.sh --version "$VERSION" --build "$BUILD_NUMBER"

codesign --verify --deep --strict "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo
echo "Herdr Island $VERSION ($BUILD_NUMBER, $COMMIT)"
echo "  $ZIP"
echo "  $ZIP.sha256"
