#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-dist/MonitorSwitch.app}"
PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile}"
DETAILS="$(codesign -dv --verbose=2 "$APP" 2>&1)"
if [[ "$DETAILS" != *"Authority=Developer ID Application:"* || "$DETAILS" != *"(runtime)"* || "$DETAILS" != *"Timestamp="* ]]; then
  echo "Build the app with a Developer ID signature, hardened runtime and a secure timestamp first." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
TEMP_DIR="$(mktemp -d /private/tmp/monitorswitch-notary.XXXXXX)"
trap 'rm -f "$TEMP_DIR/MonitorSwitch.zip"; rmdir "$TEMP_DIR"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$TEMP_DIR/MonitorSwitch.zip"
xcrun notarytool submit "$TEMP_DIR/MonitorSwitch.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
