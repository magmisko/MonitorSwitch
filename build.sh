#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
MKLOCK_TOOL="${MKLOCK_TOOL:-$HOME/Library/Application Support/MK Locks/mklock}"
if [[ -x "$MKLOCK_TOOL" && "${MONITORSWITCH_BUILD_LOCKED:-0}" != "1" ]]; then
  exec "$MKLOCK_TOOL" build "MonitorSwitch: build" env MONITORSWITCH_BUILD_LOCKED=1 taskpolicy -b nice -n 19 /bin/bash "$PWD/build.sh" "$@"
fi
OUT="${1:-dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/MonitorSwitch.app"
SDK_VERSION="$(xcrun --show-sdk-version)"
SDK_PATH="$(xcrun --show-sdk-path)"
MIN_VERSION=14.0
python3 scripts/validate_profiles.py
mkdir -p build/ModuleCache "$APP/Contents/MacOS" "$APP/Contents/Resources"
LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_VERSION" -Xlinker "$SDK_VERSION")
xcrun clang -Os -fmodules -fmodules-cache-path="$PWD/build/ModuleCache" \
  -isysroot "$SDK_PATH" -mmacosx-version-min="$MIN_VERSION" \
  -I Vendor/m1ddc DDCBridge.m Vendor/m1ddc/ioregistry.m \
  -framework Foundation -framework IOKit -framework CoreGraphics -framework CoreDisplay \
  "${LINK_FLAGS[@]}" -o "$APP/Contents/Resources/ddc-bridge"
xcrun swiftc -O -sdk "$SDK_PATH" -target "arm64-apple-macos$MIN_VERSION" \
  -module-cache-path "$PWD/build/ModuleCache" -framework AppKit -framework Carbon \
  "${LINK_FLAGS[@]}" main.swift -o "$APP/Contents/MacOS/InputSwitch"
cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp monitors.json "$APP/Contents/Resources/monitors.json"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InputSwitch</string>
<key>CFBundleIdentifier</key><string>sk.mk.InputSwitch</string>
<key>CFBundleName</key><string>MonitorSwitch</string>
<key>CFBundleDisplayName</key><string>MonitorSwitch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
for binary in "$APP/Contents/MacOS/InputSwitch" "$APP/Contents/Resources/ddc-bridge"; do
  ACTUAL_SDK="$(otool -l "$binary" | awk '/LC_BUILD_VERSION/ {found=1;next} found && $1 == "sdk" {print $2;exit}')"
  if [[ "$ACTUAL_SDK" != "$SDK_VERSION" ]]; then
    echo "SDK mismatch: $ACTUAL_SDK != $SDK_VERSION" >&2
    exit 1
  fi
done
IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/ddc-bridge"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
du -sh "$APP"
