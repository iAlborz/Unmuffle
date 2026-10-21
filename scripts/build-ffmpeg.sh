#!/bin/zsh
# Builds the ffmpeg that ships inside Unmuffle.app into vendor/ffmpeg:
# ffmpeg and ffprobe plus their shared libraries, universal (Apple Silicon + Intel), LGPL only.
# No GPL or non-free parts are enabled, so the app can be distributed under the MIT license and
# on the Mac App Store. Video encoding uses Apple's VideoToolbox hardware encoders.
# Takes about 10 minutes. build.sh copies the result into the app.
set -e
cd "$(dirname "$0")/.."
VERSION=9.0.2
SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
ROOT="$PWD"
WORK="$ROOT/.build/ffmpeg"
OUT="$ROOT/vendor/ffmpeg"
mkdir -p "$WORK"
cd "$WORK"

TARBALL="ffmpeg-$VERSION.tar.xz"
[ -f "$TARBALL" ] || curl -fL -o "$TARBALL" "https://ffmpeg.org/releases/$TARBALL"
echo "$SHA256  $TARBALL" | shasum -a 256 -c -

for ARCH in arm64 x86_64; do
  SRC="$WORK/src-$ARCH"
  rm -rf "$SRC" "$WORK/install-$ARCH"
  mkdir -p "$SRC"
  tar -xf "$TARBALL" -C "$SRC" --strip-components 1
  EXTRA=()
  # The Intel build is cross-compiled; without nasm it uses the C code paths.
  [ "$ARCH" = x86_64 ] && EXTRA=(--enable-cross-compile --disable-x86asm)
  (cd "$SRC" && ./configure \
    --prefix="$WORK/install-$ARCH" \
    --arch=$ARCH --target-os=darwin --cc="clang -arch $ARCH" $EXTRA \
    --extra-cflags="-mmacosx-version-min=14.0" --extra-ldflags="-mmacosx-version-min=14.0" \
    --enable-shared --disable-static --install-name-dir='@executable_path/../Frameworks' \
    --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
    --disable-doc --disable-ffplay --disable-avdevice --disable-network \
    --disable-encoders \
    --enable-encoder=aac,pcm_s16le,pcm_f32le,h264_videotoolbox,hevc_videotoolbox \
    && make -j"$(sysctl -n hw.ncpu)" && make install)
done

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"
for f in ffmpeg ffprobe; do
  lipo -create "$WORK/install-arm64/bin/$f" "$WORK/install-x86_64/bin/$f" -output "$OUT/bin/$f"
done
# The binaries load the libraries by their major-version name (libavcodec.63.dylib, ...).
for lib in "$WORK"/install-arm64/lib/lib*.dylib; do
  name=${lib:t}
  [[ $name =~ '^lib[a-z]+\.[0-9]+\.dylib$' ]] || continue
  lipo -create "$lib" "$WORK/install-x86_64/lib/$name" -output "$OUT/lib/$name"
done
cp "$WORK/src-arm64/COPYING.LGPLv2.1" "$OUT/LICENSE.txt"
echo "FFmpeg $VERSION, built by scripts/build-ffmpeg.sh from https://ffmpeg.org/releases/$TARBALL" > "$OUT/SOURCE.txt"
echo "Built $OUT"
