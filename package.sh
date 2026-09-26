#!/usr/bin/env bash
# Build a release zip that extracts to Interface/AddOns/StickyCustomChannels/
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(sed -n 's/^## Version: *//p' StickyCustomChannels.toc)
OUT="dist/StickyCustomChannels-${VERSION}.zip"
mkdir -p dist build/StickyCustomChannels
cp -r StickyCustomChannels.toc StickyCustomChannels.lua LICENSE media build/StickyCustomChannels/
rm -f "$OUT"
(cd build && zip -qr "../$OUT" StickyCustomChannels)
rm -rf build
echo "built $OUT"
