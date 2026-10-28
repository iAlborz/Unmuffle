#!/bin/zsh
# Captures the start screen, Instant, Simple and Advanced mode of the app in one language.
# Usage: capture.sh <app> <sample.mp4> <lang> "<file name shown in the title bar>" <out dir> ["<more Instant mode file names>" ...]
set -e
# APP as the real path (/private/var/…), the way it appears in the process list, so pkill finds it.
APP="${1:A}"; SAMPLE="$2"; LANG_CODE="$3"; NAME="$4"; OUT="$5"; shift 5
mkdir -p "$OUT"
cp "$SAMPLE" "$OUT/$NAME.mp4"
snap() {  # snap <file> [app args...] — the app writes a picture of its window 9 seconds after launch
  local file=$1; shift
  for try in 1 2 3; do
    rm -f "$OUT/$file"
    # Through `open`, so macOS brings the window to the front even while another app is in use.
    open -n -a "$APP" --env UNMUFFLE_SNAPSHOT="$OUT/$file" \
      --args "$@" -AppleLanguages "(\"$LANG_CODE\")" -autoplay '<false/>'
    for i in {1..60}; do [ -s "$OUT/$file" ] && break; sleep 0.5; done  # up to 30 s (first launch can be slow)
    sleep 0.5
    pkill -f "$APP/Contents/MacOS/Unmuffle" || true
    while pgrep -qf "$APP/Contents/MacOS/Unmuffle"; do sleep 0.2; done
    # Another app in front leaves the window inactive, with grey buttons. Try again if the close button isn't red.
    [ "$(magick "$OUT/$file" -quiet -crop 1x1+52+51 -format '%[fx:int(255*r)]' info:)" -gt 200 ] && break
  done
}
snap drop.png -mode simple
snap simple.png "$OUT/$NAME.mp4" -mode simple
snap adv.png "$OUT/$NAME.mp4" -mode advanced
# Instant mode: the sample under each name. The first two are cut short so they are saved in the picture;
# the third is long, so it is still being saved.
mkdir -p "$OUT/instant"
files=("$OUT/instant/$NAME.mp4")
for n in "$@"; do files+=("$OUT/instant/$n.mp4"); done
for f in $files; do cp "$SAMPLE" "$f"; done
for f in $files[1,2]; do "$APP/Contents/MacOS/ffmpeg" -v error -y -i "$SAMPLE" -t 4 -c copy "$f"; done
"$APP/Contents/MacOS/ffmpeg" -v error -y -stream_loop 40 -i "$SAMPLE" -c copy "$files[3]"
snap instant.png -mode instant $files
pkill -f "$OUT/instant/" || true  # the ffmpeg still saving
rm -rf "${OUT:?}/instant" "$OUT/$NAME.mp4"
