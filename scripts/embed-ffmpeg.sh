#!/bin/zsh
# Copies the bundled ffmpeg (vendor/ffmpeg) into an app and signs it. Used by build.sh and the
# Xcode project. Builds vendor/ffmpeg first if it is missing.
# Usage: scripts/embed-ffmpeg.sh path/to/Unmuffle.app [signing identity, default "-" for ad hoc]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
ID="${2:--}"
[ -d "$ROOT/vendor/ffmpeg" ] || "$ROOT/scripts/build-ffmpeg.sh"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/vendor/ffmpeg/bin/ffmpeg" "$ROOT/vendor/ffmpeg/bin/ffprobe" "$APP/Contents/MacOS/"
cp "$ROOT"/vendor/ffmpeg/lib/*.dylib "$APP/Contents/Frameworks/"
cp "$ROOT/vendor/ffmpeg/LICENSE.txt" "$APP/Contents/Resources/FFmpeg-LICENSE.txt"
cp "$ROOT/vendor/ffmpeg/SOURCE.txt" "$APP/Contents/Resources/FFmpeg-SOURCE.txt"
# Sign inside out. The helpers need their own sandbox entitlements to run in the app's sandbox.
codesign --force --sign "$ID" "$APP"/Contents/Frameworks/*.dylib
codesign --force --sign "$ID" --entitlements "$ROOT/Resources/Helper.entitlements" \
  "$APP/Contents/MacOS/ffmpeg" "$APP/Contents/MacOS/ffprobe"
