#!/bin/zsh
# Makes the 2560×1600 Mac App Store screenshots in every language into docs/screenshots/<lang>/.
# Needs a built app (./build.sh), Google Chrome, ImageMagick, and a test video with speech.
# Usage: scripts/screenshots/make.sh path/to/sample.mp4 [lang ...]   (default: every language in docs/app-store-listing)
set -e
cd "$(dirname "$0")/../.."
ROOT="$PWD"; HERE="$ROOT/scripts/screenshots"; WORK="$ROOT/.build/screenshots"
SAMPLE="${1:A}"; shift
LANGS=("$@")
[ ${#LANGS} -gt 0 ] || LANGS=(${(f)"$(ls docs/app-store-listing | sed 's/\.json$//')"})
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {  # render <url> <out.png> <width> <height>
  # A fresh profile each time, or a lingering Chrome takes over the next render. Chrome's exit code is
  # unreliable here, so check for the file instead.
  local profile=$(mktemp -d)
  rm -f "$2"
  "$CHROME" --headless=new --user-data-dir="$profile" --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=$3,$4 --virtual-time-budget=3000 --screenshot="$2" "$1" >/dev/null 2>&1 || true
  rm -rf "$profile"
  [ -s "$2" ] || { echo "render failed: $1" >&2; return 1; }
}
mkdir -p "$WORK"
# An unsandboxed copy of the app, so it can read the sample and write snapshots anywhere.
rm -rf "$WORK/Unmuffle.app"
cp -R build/Unmuffle.app "$WORK/"
codesign --force --sign - "$WORK/Unmuffle.app/Contents/MacOS/ffmpeg" "$WORK/Unmuffle.app/Contents/MacOS/ffprobe" 2>/dev/null
codesign --force --sign - "$WORK/Unmuffle.app" 2>/dev/null
cp "$HERE/compose.html" "$WORK/"
render "file://$HERE/frame.svg" "$WORK/frame.png" 1280 720
for L in $LANGS; do
  NAME=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['sampleFile'])" "docs/app-store-listing/$L.json")
  "$HERE/capture.sh" "$WORK/Unmuffle.app" "$SAMPLE" "$L" "$NAME" "$WORK/$L"
done
# data.js: texts, snapshot sizes and where the video goes in each snapshot.
python3 - "$WORK" $LANGS <<'PY'
import json, subprocess, sys
work, langs = sys.argv[1], sys.argv[2:]
data = {}
for L in langs:
    texts = json.load(open(f"docs/app-store-listing/{L}.json"))["screens"]
    data[L] = {}
    for screen in ["simple", "adv", "drop"]:
        img = f"{L}/{screen}.png"
        w, h = map(int, subprocess.check_output(["magick", "identify", "-quiet", "-format", "%w %h", f"{work}/{img}"]).split())
        video = None
        if screen != "drop":
            x, y, bw, bh = map(int, subprocess.check_output(
                ["python3", "scripts/screenshots/player_rect.py", f"{work}/{img}"]).decode().split(","))
            vh = min(bh, round(bw * 9 / 16)); vw = round(vh * 16 / 9)  # the 16:9 test video, centered in the black area
            video = [x + (bw - vw) / 2, y + (bh - vh) / 2, vw, vh]
        data[L][screen] = {"img": img, "w": w, "h": h, "video": video, **texts[screen]}
open(f"{work}/data.js", "w").write("window.DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
PY
for L in $LANGS; do
  mkdir -p "docs/screenshots/$L"
  for SCREEN in simple adv drop; do
    render "file://$WORK/compose.html#$L/$SCREEN" "docs/screenshots/$L/$SCREEN.png" 2560 1600
    magick "docs/screenshots/$L/$SCREEN.png" -quiet -strip "docs/screenshots/$L/$SCREEN.png"
  done
  echo "$L done"
done
