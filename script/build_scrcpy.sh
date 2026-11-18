#!/bin/zsh
# Rebuild the pinned scrcpy client with our native Cocoa toolbar. Upstream
# vendor binaries/server are untouched; no runtime injection or permissions.
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
for tool in cmake meson ninja pkg-config nasm autoreconf automake glibtoolize; do
  command -v "$tool" >/dev/null || { print -u2 "Missing build tool: $tool"; exit 2; }
done
ARCHITECTURES=("${@:-arm64 x86_64}")
if (( $# == 0 )); then ARCHITECTURES=(arm64 x86_64); fi
for architecture in "${ARCHITECTURES[@]}"; do
  [[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || exit 2
done
CACHE="$ROOT_DIR/work/community-sources"
REAL_WORK="$ROOT_DIR/work/native-runtime"
mkdir -p "$REAL_WORK"
# FFmpeg/Autotools makefiles cannot reliably build below paths with spaces.
# This alias points into the project; all outputs remain under work/.
WORK="/tmp/mirrorlink-native-$UID"
if [[ -e "$WORK" || -L "$WORK" ]]; then
  [[ -L "$WORK" && "$(readlink "$WORK")" == "$REAL_WORK" ]] || { print -u2 'Build alias belongs to another location'; exit 2; }
else
  ln -s "$REAL_WORK" "$WORK"
fi
mkdir -p "$WORK/sources" "$WORK/build" "$WORK/install" "$WORK/bin"
while read -r kind filename digest url; do
  [[ "$kind" == source ]] || continue
  [[ "$(shasum -a 256 "$CACHE/$filename" | cut -d ' ' -f1)" == "$digest" ]] || { print -u2 "Source checksum mismatch: $filename"; exit 2; }
  # Extraction is idempotent and never changes the checked-in vendor tree.
  tar -xf "$CACHE/$filename" -C "$WORK/sources"
done < "$ROOT_DIR/vendor/third-party-sources.tsv"
SCRCPY="$WORK/sources/scrcpy-4.1"
patch --silent -d "$SCRCPY" -p1 < "$ROOT_DIR/vendor/mirror-window/scrcpy.patch"
cp "$ROOT_DIR/vendor/mirror-window/MirrorWindowToolbar.m" "$SCRCPY/app/src/mirrorlink_toolbar.m"
cp "$ROOT_DIR/vendor/mirror-window/MirrorWindowToolbar.h" "$SCRCPY/app/src/mirrorlink_toolbar.h"
JOBS="${MIRRORLINK_BUILD_JOBS:-6}"
for architecture in "${ARCHITECTURES[@]}"; do
  PREFIX="$WORK/install/$architecture"
  BUILD="$WORK/build/$architecture"
  MACHINE="$ROOT_DIR/vendor/mirror-window/$architecture.ini"
  mkdir -p "$PREFIX" "$BUILD"
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
  unset PKG_CONFIG_PATH
  export MACOSX_DEPLOYMENT_TARGET=13.0
  export CC="/usr/bin/clang -arch $architecture -mmacosx-version-min=13.0"
  export CFLAGS='-O2 -fPIC'
  if [[ ! -f "$PREFIX/.dependencies-complete-v2" ]]; then
    print "==> $architecture: pinned SDL / dav1d / zlib / FFmpeg / libusb"
    cmake -S "$WORK/sources/SDL-release-3.4.12" -B "$BUILD/sdl" -G Ninja \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="$architecture" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF
    cmake --build "$BUILD/sdl" -j "$JOBS"
    cmake --install "$BUILD/sdl"
    if [[ ! -f "$BUILD/dav1d/build.ninja" ]]; then
      meson setup "$BUILD/dav1d" "$WORK/sources/dav1d-1.5.3" --cross-file="$MACHINE" \
        --prefix="$PREFIX" --libdir=lib --buildtype=release --default-library=static \
        -Denable_tests=false -Denable_tools=false
    fi
    ninja -C "$BUILD/dav1d" -j "$JOBS" install
    mkdir -p "$BUILD/zlib"
    (cd "$BUILD/zlib" && "$WORK/sources/zlib-1.3.2/configure" --static --prefix="$PREFIX" && make -j "$JOBS" && make install)
    mkdir -p "$BUILD/ffmpeg"
    (
      cd "$BUILD/ffmpeg"
      "$WORK/sources/ffmpeg-8.1.2/configure" --prefix="$PREFIX" --cc="$CC" \
        --arch="$architecture" --target-os=darwin --enable-cross-compile \
        --pkg-config-flags=--static --extra-cflags="-O2 -fPIC -mmacosx-version-min=13.0" \
        --extra-ldflags="-mmacosx-version-min=13.0" \
        --disable-programs --disable-doc --disable-swscale --disable-avfilter --disable-avdevice \
        --disable-network --disable-everything --disable-vulkan --disable-vaapi --disable-vdpau \
        --enable-swresample --enable-libdav1d --enable-zlib --enable-static --disable-shared \
        --enable-decoder=h264,hevc,av1,vp8,vp9,libdav1d,pcm_s16le,opus,aac,flac,png \
        --enable-protocol=file --enable-demuxer=image2 --enable-parser=png \
        --enable-muxer=matroska,mp4,opus,flac,wav
      make -j "$JOBS"
      make install
    )
    mkdir -p "$BUILD/libusb"
    (cd "$WORK/sources/libusb-1.0.30" && ./bootstrap.sh)
    (cd "$BUILD/libusb" && ac_cv_func_pipe2=no "$WORK/sources/libusb-1.0.30/configure" \
      --host="$architecture-apple-darwin" --prefix="$PREFIX" --enable-static --disable-shared \
      && make -j "$JOBS" && make install)
    touch "$PREFIX/.dependencies-complete-v2"
  fi
  print "==> $architecture: scrcpy 4.1 + MirrorLink native toolbar"
  if [[ ! -f "$BUILD/scrcpy/build.ninja" ]]; then
    meson setup "$BUILD/scrcpy" "$SCRCPY" --cross-file="$MACHINE" \
      --buildtype=release --strip -Dcompile_server=false -Dportable=true -Dstatic=true
  fi
  ninja -C "$BUILD/scrcpy" -j "$JOBS"
  cp "$BUILD/scrcpy/app/scrcpy" "$WORK/bin/scrcpy-$architecture"
  xcrun strip -S "$WORK/bin/scrcpy-$architecture"
  lipo -verify_arch "$architecture" "$WORK/bin/scrcpy-$architecture"
done
