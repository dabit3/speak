#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_IDENTITY="$(bash "$ROOT/scripts/signing-identity.sh")"
APP="$ROOT/build/artifacts.noindex/Speak.app"
swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/AppIcon.iconset"
cp "$BIN/Speak" "$APP/Contents/MacOS/Speak"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
swiftc "$ROOT/Sources/SpeakCore/SpeakLogo.swift" "$ROOT/scripts/icon.swift" -o "$ROOT/.build/speak-icon-generator"
"$ROOT/.build/speak-icon-generator" "$ROOT/build/AppIcon.iconset" "$ROOT/Resources"
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --entitlements "$ROOT/Resources/Speak.entitlements" "$APP"
else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ROOT/Resources/Speak.entitlements" "$APP"
fi
codesign --verify --deep --strict "$APP"
printf '\nBuilt %s\nLaunch with: open "%s"\n' "$APP" "$APP"
