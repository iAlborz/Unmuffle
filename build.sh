#!/bin/zsh
# Builds Unmuffle.app into ./build
# ./build.sh --universal builds for both Apple Silicon and Intel (used for releases).
set -e
cd "$(dirname "$0")"
ARCHS=()
[ "$1" = "--universal" ] && ARCHS=(--arch arm64 --arch x86_64)
# Command Line Tools 27 ship a macOS 27 SDK whose SwiftUI needs a macro plugin that only
# Xcode.app provides. Build against the macOS 26 SDK when it is present.
SDK26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [ -d "$SDK26" ]; then
  swift build -c release $ARCHS --sdk "$SDK26"
else
  swift build -c release $ARCHS
fi
APP="build/Unmuffle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Unmuffle "$APP/Contents/MacOS/Unmuffle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The version and build number are set in the Xcode project (General tab). Fill them in as Xcode does.
setting() { grep -m1 -E "[[:space:]]$1 = " Unmuffle.xcodeproj/project.pbxproj | sed -E 's/.*= (.*);/\1/'; }
plutil -replace CFBundleShortVersionString -string "$(setting MARKETING_VERSION)" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(setting CURRENT_PROJECT_VERSION)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# sharingd/AirDrop quarantine + ad-hoc sign makes Gatekeeper say the app is
# damaged and offer to move it to Trash. Strip that before signing.
xattr -cr "$APP" 2>/dev/null || true
scripts/embed-ffmpeg.sh "$APP"
codesign --force --sign - --entitlements Resources/Unmuffle.entitlements "$APP"
echo "Built $PWD/$APP"
