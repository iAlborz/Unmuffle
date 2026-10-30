#!/bin/zsh
# Prepares a GitHub release from the version in the Xcode project:
#   1. builds the universal app signed with the Developer ID certificate, has Apple notarize it (needs the
#      "unmuffle" profile from `xcrun notarytool store-credentials`) and zips it to build/Unmuffle.zip,
#   2. signs the zip for Sparkle and adds it to appcast.xml (needs the "unmuffle" key in the Keychain).
# Write docs/release-notes/<version>.md first. Then publish:
#   gh release create v<version> build/Unmuffle.zip --title "Unmuffle <version>" --notes-file docs/release-notes/<version>.md
#   git commit appcast.xml && git push   (users get the update once the appcast is pushed)
set -e
cd "$(dirname "$0")/.."
SIGN_ID="Developer ID Application" ./build.sh --universal
APP=build/Unmuffle.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
NOTES="docs/release-notes/$VERSION.md"
[ -f "$NOTES" ] || { echo "Write $NOTES first." >&2; exit 1; }
rm -f build/Unmuffle.zip
ditto -c -k --keepParent "$APP" build/Unmuffle.zip
# Notarize, then staple the ticket to the app so it opens without a warning, even offline, and zip it again.
xcrun notarytool submit build/Unmuffle.zip --keychain-profile unmuffle --wait
xcrun stapler staple "$APP"
rm build/Unmuffle.zip
ditto -c -k --keepParent "$APP" build/Unmuffle.zip
python3 scripts/appcast.py appcast.xml build/Unmuffle.zip "$VERSION" "$BUILD" \
  "https://github.com/iAlborz/Unmuffle/releases/download/v$VERSION/Unmuffle.zip" "$NOTES"
shasum -a 256 build/Unmuffle.zip
