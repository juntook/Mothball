#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Fetches the Sparkle xcframework into Vendor/ for offline/local builds.
# Normally SwiftPM downloads the binary artifact itself; use this (plus
# MOTHBALL_LOCAL_SPARKLE=1) when SwiftPM's downloader can't reach GitHub
# (restricted networks, sandboxes).
#
#   ./scripts/fetch-sparkle.sh
#   MOTHBALL_LOCAL_SPARKLE=1 swift build
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.9.4"
SHA256="cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"

if [[ -d Vendor/Sparkle.xcframework ]]; then
    echo "Vendor/Sparkle.xcframework already present"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "==> Downloading Sparkle $VERSION"
curl -sL -o "$tmp/sparkle.zip" "$URL"
echo "$SHA256  $tmp/sparkle.zip" | shasum -a 256 -c -
mkdir -p Vendor
unzip -qo "$tmp/sparkle.zip" 'Sparkle.xcframework/*' -d Vendor
echo "==> Vendor/Sparkle.xcframework ready"
