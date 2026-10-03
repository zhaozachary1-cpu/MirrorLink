#!/bin/zsh
# Retrieve pinned upstream materials. Never alter the runtime or its signatures.
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CACHE="$ROOT_DIR/work/community-sources"
LICENSES="$ROOT_DIR/vendor/licenses"
mkdir -p "$CACHE" "$LICENSES"

while read -r kind filename digest url; do
  [[ -z "$kind" || "$kind" == \#* ]] && continue
  if [[ ! -f "$CACHE/$filename" ]]; then
    echo "获取上游发行材料：$filename"
    curl --fail --silent --show-error --location --retry 2 --connect-timeout 20 --max-time 600 \
      "$url" -o "$CACHE/$filename.download"
    actual="$(shasum -a 256 "$CACHE/$filename.download" | cut -d ' ' -f1)"
    [[ "$actual" == "$digest" ]] || { print -u2 "校验失败：$filename"; exit 1; }
    mv "$CACHE/$filename.download" "$CACHE/$filename"
  fi
  [[ "$(shasum -a 256 "$CACHE/$filename" | cut -d ' ' -f1)" == "$digest" ]] || { print -u2 "缓存校验失败：$filename"; exit 1; }
done < "$ROOT_DIR/vendor/third-party-sources.tsv"

TEMP_BASE="$ROOT_DIR/work/tmp"
mkdir -p "$TEMP_BASE"
STAGE="$(mktemp -d "$TEMP_BASE/mirrorlink-licenses.XXXXXX")"
cleanup() {
  if [[ "$STAGE" == "$TEMP_BASE"/mirrorlink-licenses.* && -d "$STAGE" && ! -L "$STAGE" ]]; then
    rm -rf -- "$STAGE"
  fi
}
trap cleanup EXIT
while read -r kind filename digest url; do
  [[ -z "$kind" || "$kind" == \#* ]] && continue
  case "$filename" in
    *.tar.gz|*.tar.xz) tar -xf "$CACHE/$filename" -C "$STAGE" ;;
  esac
done < "$ROOT_DIR/vendor/third-party-sources.tsv"
unzip -q "$CACHE/platform-tools_r37.0.0-darwin.zip" \
  platform-tools/adb platform-tools/NOTICE.txt platform-tools/source.properties -d "$STAGE"

for architecture in arm64 x86_64; do
  upstream_arch="$architecture"
  [[ "$architecture" == arm64 ]] && upstream_arch=aarch64
  for resource in adb scrcpy scrcpy-server scrcpy.png disconnected.png LICENSE; do
    cmp "$ROOT_DIR/vendor/scrcpy/$architecture/$resource" \
      "$STAGE/scrcpy-macos-$upstream_arch-v4.1/$resource"
  done
  cmp "$ROOT_DIR/vendor/scrcpy/$architecture/adb" "$STAGE/platform-tools/adb"
done

cp "$STAGE/platform-tools/NOTICE.txt" "$LICENSES/NOTICE-Android-Platform-Tools-37.0.0.txt"
cp "$STAGE/platform-tools/source.properties" "$LICENSES/Android-Platform-Tools-source.properties"
cp "$STAGE/ffmpeg-8.1.2/COPYING.LGPLv2.1" "$LICENSES/FFmpeg-COPYING.LGPLv2.1"
cp "$STAGE/ffmpeg-8.1.2/LICENSE.md" "$LICENSES/FFmpeg-LICENSE.md"
cp "$STAGE/SDL-release-3.4.12/LICENSE.txt" "$LICENSES/SDL-LICENSE.txt"
cp "$STAGE/libusb-1.0.30/COPYING" "$LICENSES/libusb-COPYING"
cp "$STAGE/dav1d-1.5.3/COPYING" "$LICENSES/dav1d-COPYING"
cp "$STAGE/zlib-1.3.2/LICENSE" "$LICENSES/zlib-LICENSE"
(
  cd "$LICENSES"
  shasum -a 256 Android-Platform-Tools-source.properties FFmpeg-COPYING.LGPLv2.1 \
    FFmpeg-LICENSE.md NOTICE-Android-Platform-Tools-37.0.0.txt SDL-LICENSE.txt \
    libusb-COPYING dav1d-COPYING zlib-LICENSE > SHA256SUMS.txt
)
echo '全部归档哈希与内置运行时逐字节匹配；已收录完整上游许可文本。'
