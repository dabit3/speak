#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/artifacts.noindex/Speak.app"

if [[ ! -d "$APP" ]]; then
    printf 'Build the app first with: bash scripts/build.sh\n' >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/Speak")"
case "$ARCHITECTURES" in
    arm64) ARCH="arm64" ;;
    x86_64) ARCH="x86_64" ;;
    "x86_64 arm64"|"arm64 x86_64") ARCH="universal" ;;
    *) printf 'Unsupported app architectures: %s\n' "$ARCHITECTURES" >&2; exit 1 ;;
esac
if [[ ! "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    printf 'The app version contains invalid filename characters.\n' >&2
    exit 1
fi

DMG="$ROOT/build/Speak-$VERSION-$ARCH.dmg"
if [[ -e "$DMG" ]]; then
    printf 'The installer already exists: %s\nMove it before packaging another copy.\n' "$DMG" >&2
    exit 1
fi

mkdir -p "$ROOT/.build"
WORK="$(mktemp -d "$ROOT/.build/dmg.XXXXXX")"
STAGING="$WORK/content"
MOUNT="$WORK/mount"
mkdir -p "$STAGING" "$MOUNT"
ditto "$APP" "$STAGING/Speak.app"
ln -s /Applications "$STAGING/Applications"
codesign --verify --deep --strict "$STAGING/Speak.app"
hdiutil create -volname Speak -srcfolder "$STAGING" -nospotlight -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
codesign --verify --deep --strict "$MOUNT/Speak.app"
cmp "$APP/Contents/MacOS/Speak" "$MOUNT/Speak.app/Contents/MacOS/Speak"
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == /Applications ]]
hdiutil detach "$MOUNT"
trap - EXIT
shasum -a 256 "$DMG" > "$DMG.sha256"
printf '\nCreated and verified: %s\nChecksum: %s.sha256\nOpen the DMG and drag Speak into Applications.\n' "$DMG" "$DMG"
