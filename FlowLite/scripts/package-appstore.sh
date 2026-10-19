#!/usr/bin/env bash
# Builds a signed installer package for the Mac App Store: build/FlowLite-AppStore.pkg
#
# Needs an Apple Developer Program membership and, in your login keychain:
#   - an "Apple Distribution" (or "3rd Party Mac Developer Application") certificate
#   - a "3rd Party Mac Developer Installer" certificate
# plus a Mac App Store provisioning profile for BUNDLE_ID.
#
# Usage:
#   BUNDLE_ID=com.example.flowlite \
#   TEAM_ID=ABCDE12345 \
#   APP_IDENTITY="Apple Distribution: Your Name (ABCDE12345)" \
#   INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (ABCDE12345)" \
#   PROFILE=~/Downloads/FlowLite_Mac_App_Store.provisionprofile \
#   ./scripts/package-appstore.sh
#
# Then upload build/FlowLite-AppStore.pkg with the Transporter app, or:
#   xcrun altool --upload-package build/FlowLite-AppStore.pkg --type macos \
#     --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
for var in BUNDLE_ID TEAM_ID APP_IDENTITY INSTALLER_IDENTITY PROFILE; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
done
if (( ${#missing[@]} )); then
    echo "error: set ${missing[*]} (see the usage notes at the top of this script)" >&2
    exit 2
fi
[[ -f "$PROFILE" ]] || { echo "error: provisioning profile not found at $PROFILE" >&2; exit 2; }

./scripts/build-app.sh
APP="build/FlowLite.app"
PKG="build/FlowLite-AppStore.pkg"
ENTITLEMENTS="build/AppStore.generated.entitlements"

# The App Store build needs your bundle ID and the profile embedded in the app.
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Sandbox entitlements plus the identifiers App Store Connect checks.
cp Support/AppStore.entitlements "$ENTITLEMENTS"
# PlistBuddy, not plutil: plutil reads the dots in these keys as nested key paths.
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"

codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
echo "Built $PKG"
echo "Upload it with Transporter, or: xcrun altool --upload-package $PKG --type macos --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
