#!/usr/bin/env bash
# Builds a signed, notarized disk image for direct download: build/Whisperwell.dmg
# This route needs no App Sandbox, so every Whisperwell feature works as-is.
#
# Needs an Apple Developer Program membership, a "Developer ID Application" certificate
# in your login keychain, and a notarization profile saved once with:
#   xcrun notarytool store-credentials whisperwell-notary \
#     --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>
#
# Usage:
#   BUNDLE_ID=com.example.whisperwell \
#   APP_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
#   NOTARY_PROFILE=whisperwell-notary \
#   ./scripts/package-developer-id.sh
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
for var in BUNDLE_ID APP_IDENTITY NOTARY_PROFILE; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
done
if (( ${#missing[@]} )); then
    echo "error: set ${missing[*]} (see the usage notes at the top of this script)" >&2
    exit 2
fi

./scripts/build-app.sh
APP="build/Whisperwell.app"
DMG="build/Whisperwell.dmg"

plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
# Hardened runtime is required for notarization.
codesign --force --options runtime --timestamp \
    --entitlements Support/DeveloperID.entitlements --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# A disk image with the app and a shortcut to Applications.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Whisperwell" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "Built and notarized $DMG"
