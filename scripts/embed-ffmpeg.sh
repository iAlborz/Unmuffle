#!/bin/zsh
# Copies the bundled ffmpeg (vendor/ffmpeg) into an app and signs it. Used by build.sh and the
# Xcode project. Builds vendor/ffmpeg first if it is missing.
# Usage: scripts/embed-ffmpeg.sh path/to/Unmuffle.app [signing identity, default "-" for ad hoc] [--no-sandbox]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
ID="${2:--}"
# In the sandboxed app (App Store) the helpers must run in the app's sandbox; outside it they need nothing.
HELPER_ENTITLEMENTS=(--entitlements "$ROOT/Resources/Helper.entitlements")
[ "$3" = "--no-sandbox" ] && HELPER_ENTITLEMENTS=()
[ -d "$ROOT/vendor/ffmpeg" ] || "$ROOT/scripts/build-ffmpeg.sh"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/vendor/ffmpeg/bin/ffmpeg" "$ROOT/vendor/ffmpeg/bin/ffprobe" "$APP/Contents/MacOS/"
cp "$ROOT"/vendor/ffmpeg/lib/*.dylib "$APP/Contents/Frameworks/"
cp "$ROOT/vendor/ffmpeg/LICENSE.txt" "$APP/Contents/Resources/FFmpeg-LICENSE.txt"
cp "$ROOT/vendor/ffmpeg/SOURCE.txt" "$APP/Contents/Resources/FFmpeg-SOURCE.txt"
# Sign inside out. A Developer ID build gets notarized, which needs the hardened runtime and a secure timestamp.
OPTS=()
[[ "$ID" == "Developer ID"* ]] && OPTS=(--options runtime --timestamp)
codesign --force --sign "$ID" $OPTS "$APP"/Contents/Frameworks/*.dylib
codesign --force --sign "$ID" $OPTS $HELPER_ENTITLEMENTS "$APP/Contents/MacOS/ffmpeg" "$APP/Contents/MacOS/ffprobe"
