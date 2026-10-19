#!/usr/bin/env bash
# Builds build/Whisperwell.app: a release binary, the Info.plist (for the microphone prompt),
# and a code signature so macOS can track its privacy permissions.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Whisperwell
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Whisperwell.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Whisperwell" "$APP/Contents/MacOS/Whisperwell"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# Sign with a stable local certificate when available, so macOS keeps Whisperwell's privacy
# permissions across rebuilds. A temporary (ad-hoc) signature changes every build, and macOS
# then treats each build as a new app. See "Development signing" in the README.
DEV_IDENTITY="${DEV_IDENTITY:-Whisperwell Development}"
# Certificates made before the rename are named "FlowLite Development"; keep using one if it exists.
if ! security find-identity -p codesigning | grep -q "\"$DEV_IDENTITY\"" \
    && security find-identity -p codesigning | grep -q "\"FlowLite Development\""; then
    DEV_IDENTITY="FlowLite Development"
fi
if security find-identity -p codesigning | grep -q "\"$DEV_IDENTITY\""; then
    codesign --force --sign "$DEV_IDENTITY" "$APP"
else
    echo "warning: no \"$DEV_IDENTITY\" certificate; using an ad-hoc signature. Permissions will reset after each rebuild." >&2
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "Run it with: open $APP"
