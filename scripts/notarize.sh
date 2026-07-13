#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Submits a dmg to Apple notarization and staples the ticket.
#
# One-time setup (stores credentials in the keychain):
#   xcrun notarytool store-credentials mothball-notary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
# Usage: scripts/notarize.sh dist/Mothball-<version>.dmg [keychain-profile]
set -euo pipefail

DMG="${1:?usage: notarize.sh <dmg> [keychain-profile]}"
PROFILE="${2:-mothball-notary}"

echo "==> Submitting $DMG (profile: $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "==> Done. Upload $DMG to the GitHub release."
echo "    Then regenerate the Sparkle appcast (same tool CI uses):"
echo "    python3 scripts/gen-appcast.py <dmg> <short-version> <build> <download-url> > dist/appcast.xml"
echo "    and upload appcast.xml to the release; the app reads it from releases/latest/download/appcast.xml."
