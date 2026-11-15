#!/bin/bash
set -euo pipefail

usage() {
  echo "usage: Scripts/bump-tap.sh <version> [tap checkout]   (example: 0.3.0)" >&2
  echo "       default tap checkout: ../homebrew-tap" >&2
  exit 2
}

[ $# -ge 1 ] || usage

VERSION="${1#v}"
TAP="${2:-../homebrew-tap}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid version: $VERSION" >&2
  usage
fi

CASK="$TAP/Casks/herdr-island.rb"
[ -f "$CASK" ] || { echo "no cask at $CASK" >&2; exit 1; }

REPO="arronKler/herdr-island"
SHA_URL="https://github.com/$REPO/releases/download/v$VERSION/HerdrIsland-$VERSION.zip.sha256"
SHA="$(curl -fsSL "$SHA_URL" | awk '{print $1}')"
if ! [[ "$SHA" =~ ^[0-9a-f]{64}$ ]]; then
  echo "could not read a checksum from $SHA_URL" >&2
  exit 1
fi

ruby -e '
  path, version, sha = ARGV
  text = File.read(path)
  changed = false
  [[/^  version ".*"$/, %(  version "#{version}")],
   [/^  sha256 ".*"$/, %(  sha256 "#{sha}")]].each do |pattern, line|
    match = text[pattern] or abort("missing #{pattern.source}")
    next if match == line

    text = text.sub(pattern, line)
    changed = true
  end
  exit 3 unless changed
  File.write(path, text)
' "$CASK" "$VERSION" "$SHA" || status=$?
status=${status:-0}
if [ "$status" -eq 3 ]; then
  echo "cask already at $VERSION"
  exit 0
fi
[ "$status" -eq 0 ] || exit "$status"

ruby -c "$CASK"

cd "$TAP"
git add Casks/herdr-island.rb
git commit -q -m "Update Herdr Island to $VERSION"
git push origin HEAD 2>/dev/null || {
  echo "committed but not pushed; push from $TAP when ready" >&2
  exit 1
}
echo "tap updated to $VERSION ($SHA)"
