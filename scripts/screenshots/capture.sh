#!/bin/zsh
# Captures the start screen, Simple mode and Advanced mode of the app in one language.
# Usage: capture.sh <app> <sample.mp4> <lang> "<file name shown in the title bar>" <out dir>
set -e
APP="$1"; SAMPLE="$2"; LANG_CODE="$3"; NAME="$4"; OUT="$5"
mkdir -p "$OUT"
cp "$SAMPLE" "$OUT/$NAME.mp4"
snap() {  # snap <file> [app args...] — the app writes a picture of its window 9 seconds after launch
  local file=$1; shift
  rm -f "$OUT/$file"
  UNMUFFLE_SNAPSHOT="$OUT/$file" "$APP/Contents/MacOS/Unmuffle" "$@" \
    -AppleLanguages "(\"$LANG_CODE\")" -autoplay '<false/>' >/dev/null 2>&1 &
  local pid=$!
  for i in {1..60}; do [ -s "$OUT/$file" ] && break; sleep 0.5; done  # up to 30 s (first launch can be slow)
  sleep 0.5
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
}
snap drop.png
snap simple.png "$OUT/$NAME.mp4" -simpleMode '<true/>'
snap adv.png "$OUT/$NAME.mp4" -simpleMode '<false/>'
rm -f "$OUT/$NAME.mp4"
