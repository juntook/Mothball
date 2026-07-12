#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Builds Mothball.app from the SwiftPM release binary, signs it, and produces
# a dmg ready for notarization (scripts/notarize.sh).
#
# Requirements: full Xcode (for codesign toolchain), a "Developer ID
# Application" certificate in the login keychain.
#
# Environment:
#   CODESIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#                       (unset → ad-hoc signing for local testing)
#   SPARKLE_ED_KEY      Sparkle EdDSA public key for Info.plist (optional here;
#                       generate once with Sparkle's generate_keys)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/Info.plist)
APP=dist/Mothball.app
DMG="dist/Mothball-$VERSION.dmg"

echo "==> Building release binary"
swift build -c release --arch arm64

echo "==> Assembling $APP"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/arm64-apple-macosx/release/MothballApp "$APP/Contents/MacOS/MothballApp"
cp App/Info.plist "$APP/Contents/Info.plist"

# Sparkle feed configuration (only meaningful in the bundled app).
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://github.com/juntook/Mothball/releases/latest/download/appcast.xml" "$APP/Contents/Info.plist" || true
if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_ED_KEY" "$APP/Contents/Info.plist" || true
fi

# App icon.
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Resource bundles produced by SwiftPM (localizations, rule library).
for bundle in .build/arm64-apple-macosx/release/Mothball_*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sparkle framework must ship inside the app.
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -not -path "*/checkouts/*" | head -1)
if [[ -n "$SPARKLE_FRAMEWORK" ]]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/MothballApp" 2>/dev/null || true
fi

echo "==> Signing"
IDENTITY="${CODESIGN_IDENTITY:--}"
# Hardened runtime enables library validation, which rejects ad-hoc-signed
# frameworks (Sparkle) at load. It is required for notarization, so enable
# it only when signing with a real identity.
SIGN_FLAGS=(--force --timestamp --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then
    echo "    (ad-hoc, no hardened runtime — set CODESIGN_IDENTITY for a distributable build)"
    SIGN_FLAGS=(--force --sign "$IDENTITY")
else
    SIGN_FLAGS+=(--options runtime)
fi
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    # Sign nested Sparkle helpers first (inside-out).
    codesign "${SIGN_FLAGS[@]}" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
    codesign "${SIGN_FLAGS[@]}" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
    codesign "${SIGN_FLAGS[@]}" \
        "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign "${SIGN_FLAGS[@]}" --deep "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Creating $DMG"
# Standard drag-to-install layout: the app plus an /Applications symlink.
STAGING=dist/dmg-staging
rm -rf "$STAGING" && mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Mothball.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Mothball" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
if [[ "$IDENTITY" != "-" ]]; then
    # Gatekeeper assesses the dmg's own signature, not just the app inside.
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

echo "==> Done: $DMG"
echo "    Next: scripts/notarize.sh $DMG"
