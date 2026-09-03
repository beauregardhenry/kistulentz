#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
RELEASE_ROOT="$DIST_ROOT/releases"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/scripts/Info.plist")"
APP_NAME="Kistulentz"
RELEASE_NAME="$APP_NAME-$VERSION-macOS-universal"
APP_PATH="$DIST_ROOT/$APP_NAME.app"
ZIP_PATH="$RELEASE_ROOT/$RELEASE_NAME.zip"
DMG_PATH="$RELEASE_ROOT/$RELEASE_NAME.dmg"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
RELEASE_NOTES_PATH="$PROJECT_ROOT/DistributionAssets/RELEASE NOTES - $APP_NAME $VERSION.md"
mkdir -p "$BUILD_ROOT"
STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/kistulentz-release.XXXXXX")"
PAYLOAD_ROOT="$STAGING_ROOT/$APP_NAME $VERSION"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

"$PROJECT_ROOT/scripts/build-app.sh"

BUILT_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
if [[ "$BUILT_ARCHS" != *arm64* || "$BUILT_ARCHS" != *x86_64* ]]; then
    print -u2 "$RELEASE_NAME requires a universal build, but only '$BUILT_ARCHS' was produced."
    print -u2 "Install Xcode 26 or newer at /Applications/Xcode.app and run this script again."
    exit 1
fi

mkdir -p "$RELEASE_ROOT" "$PAYLOAD_ROOT"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/$APP_NAME.app"
cp "$PROJECT_ROOT/DistributionAssets/FIRST OPEN - Kistulentz.txt" "$PAYLOAD_ROOT/FIRST OPEN - Kistulentz.txt"
cp "$PROJECT_ROOT/LICENSE" "$PAYLOAD_ROOT/LICENSE"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$PAYLOAD_ROOT/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_ROOT/DistributionAssets/SOURCE CODE - Kistulentz.txt" "$PAYLOAD_ROOT/SOURCE CODE - Kistulentz.txt"
if [[ -f "$RELEASE_NOTES_PATH" ]]; then
    cp "$RELEASE_NOTES_PATH" "$PAYLOAD_ROOT/${RELEASE_NOTES_PATH:t}"
fi
ln -s /Applications "$PAYLOAD_ROOT/Applications"

rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PAYLOAD_ROOT" "$ZIP_PATH"
hdiutil create \
    -quiet \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$PAYLOAD_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

cd "$RELEASE_ROOT"
shasum -a 256 "${ZIP_PATH:t}" "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}"

print "$ZIP_PATH"
print "$DMG_PATH"
print "$CHECKSUM_PATH"
