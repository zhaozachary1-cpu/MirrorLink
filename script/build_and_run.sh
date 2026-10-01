#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="release"
VERIFY=0
SHOW_LOGS=0
LAUNCH=1
# Keep unarchived signed apps outside Documents/Desktop File Provider sync.
OUTPUT_DIR="${MIRRORLINK_OUTPUT_DIR:-$HOME/Library/Application Support/MirrorLink/Builds}"

while (( $# > 0 )); do
  argument="$1"
  shift
  case "$argument" in
    --debug) CONFIGURATION="debug" ;;
    --verify) VERIFY=1 ;;
    --logs) SHOW_LOGS=1 ;;
    --no-launch) LAUNCH=0 ;;
    --output-dir)
      if (( $# == 0 )); then
        print -u2 "--output-dir 需要一个目录路径。"
        exit 2
      fi
      OUTPUT_DIR="$1"
      shift
      ;;
    *) print -u2 "未知参数：$argument"; exit 2 ;;
  esac
done

BUILD_ID="$(date -u +%Y%m%d-%H%M%S)"
if [[ "$CONFIGURATION" == "release" ]]; then
  CONFIGURATION_DIR="Release"
else
  CONFIGURATION_DIR="Debug"
fi
SCRATCH_ARM="$ROOT_DIR/.build-mirrorlink-arm64"
SCRATCH_X86="$ROOT_DIR/.build-mirrorlink-x86_64"
STAGE_DIR="$(mktemp -d /private/tmp/mirrorlink-stage.XXXXXX)"
cleanup_stage() {
  if [[ -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" && "$STAGE_DIR" == /private/tmp/mirrorlink-stage.* ]]; then
    rm -rf -- "$STAGE_DIR"
  fi
}
trap cleanup_stage EXIT
APP_DIR="$STAGE_DIR/MirrorLink.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
OUTPUT_APP="$OUTPUT_DIR/MirrorLink-$BUILD_ID.app"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$OUTPUT_DIR"

stop_previous_app() {
  local pids
  pids=(${(f)"$(pgrep -x MirrorLink 2>/dev/null || true)"})
  if (( ${#pids[@]} > 0 )); then
    echo "==> 停止上一个镜连进程"
    kill "${pids[@]}" 2>/dev/null || true
    for _ in {1..30}; do
      pgrep -x MirrorLink >/dev/null 2>&1 || return 0
      sleep 0.1
    done
    kill -9 "${pids[@]}" 2>/dev/null || true
  fi
}

echo "==> 编译 MirrorLink ($CONFIGURATION, arm64)"
swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_ARM" --triple arm64-apple-macos13 \
  --product MirrorLink

echo "==> 编译 MirrorLink ($CONFIGURATION, x86_64)"
swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_X86" --triple x86_64-apple-macos13 \
  --product MirrorLink

ARM_BINARY="$SCRATCH_ARM/out/Products/$CONFIGURATION_DIR/MirrorLink"
X86_BINARY="$SCRATCH_X86/out/Products/$CONFIGURATION_DIR/MirrorLink"
# Support both the Xcode-backed SwiftPM layout and the standard SwiftPM layout.
if [[ ! -x "$ARM_BINARY" ]]; then
  ARM_BINARY="$(swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_ARM" --triple arm64-apple-macos13 --show-bin-path)/MirrorLink"
fi
if [[ ! -x "$X86_BINARY" ]]; then
  X86_BINARY="$(swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH_X86" --triple x86_64-apple-macos13 --show-bin-path)/MirrorLink"
fi
if [[ ! -x "$ARM_BINARY" || ! -x "$X86_BINARY" ]]; then
  print -u2 "SwiftPM 没有生成两个架构的可执行文件。"
  exit 1
fi

lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$MACOS_DIR/MirrorLink"
chmod +x "$MACOS_DIR/MirrorLink"

echo "==> 准备官方 scrcpy v4.1 运行时"
ARM_TOOLS="$ROOT_DIR/vendor/scrcpy/arm64"
X86_TOOLS="$ROOT_DIR/vendor/scrcpy/x86_64"
lipo -create "$ARM_TOOLS/scrcpy" "$X86_TOOLS/scrcpy" -output "$MACOS_DIR/scrcpy"
cp "$ARM_TOOLS/adb" "$MACOS_DIR/adb"
cp "$ARM_TOOLS/scrcpy-server" "$RESOURCES_DIR/scrcpy-server"
cp "$ARM_TOOLS/scrcpy.png" "$RESOURCES_DIR/scrcpy.png"
cp "$ARM_TOOLS/disconnected.png" "$RESOURCES_DIR/disconnected.png"
cp "$ARM_TOOLS/LICENSE" "$RESOURCES_DIR/NOTICE-scrcpy.txt"
chmod +x "$MACOS_DIR/scrcpy" "$MACOS_DIR/adb"

cp "$ROOT_DIR/Sources/MirrorLinkApp/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/README.md" "$RESOURCES_DIR/README.md"

echo "==> 嵌入 Sparkle 安全更新组件"
SPARKLE_ROOT="$SCRATCH_ARM/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$SPARKLE_FRAMEWORK"
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
cp "$SPARKLE_ROOT/LICENSE" "$RESOURCES_DIR/NOTICE-Sparkle.txt"

echo "==> 生成 MirrorLink 投屏图标"
ICON_SOURCE="$STAGE_DIR/MirrorLinkIcon.png"
swift "$ROOT_DIR/script/generate_icon.swift" --output "$ICON_SOURCE"

ICONSET_DIR="$STAGE_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

echo "==> 为内置工具及完整应用包添加本地 ad-hoc 签名"
# Sign inside out, after every resource is in place. A linker signature on the
# main executable alone does not seal Info.plist, the icon, or bundled tools.
"$ROOT_DIR/script/sign_bundle.sh" "$APP_DIR" -

if [[ "$VERIFY" == "1" ]]; then
  echo "==> 校验应用包"
  file "$MACOS_DIR/MirrorLink" "$MACOS_DIR/scrcpy" "$MACOS_DIR/adb"
  lipo -info "$MACOS_DIR/MirrorLink"
  lipo -info "$MACOS_DIR/scrcpy"
  for binary in "$MACOS_DIR/MirrorLink" "$MACOS_DIR/scrcpy" "$MACOS_DIR/adb"; do
    lipo -verify_arch arm64 "$binary"
    lipo -verify_arch x86_64 "$binary"
  done
  plutil -lint "$CONTENTS_DIR/Info.plist"
  test -x "$MACOS_DIR/MirrorLink"
  test -x "$MACOS_DIR/scrcpy"
  test -x "$MACOS_DIR/adb"
  test -f "$RESOURCES_DIR/scrcpy-server"
  test -s "$RESOURCES_DIR/AppIcon.icns"
  lipo -verify_arch arm64 x86_64 "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/Sparkle"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "==> 复制到：$OUTPUT_APP"
ditto "$APP_DIR" "$OUTPUT_APP"
# File Provider-backed output folders may attach FinderInfo to the new bundle
# root. Remove only this disallowed metadata, never quarantine/security flags.
xattr -d com.apple.FinderInfo "$OUTPUT_APP" 2>/dev/null || true
if [[ "$VERIFY" == "1" ]]; then
  codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
fi

if [[ "$SHOW_LOGS" == "1" ]]; then
  echo "应用包：$OUTPUT_APP"
  echo "构建目录：$STAGE_DIR"
fi

if [[ "$LAUNCH" == "1" ]]; then
  stop_previous_app
  echo "==> 通过 macOS open 启动应用"
  /usr/bin/open -n "$OUTPUT_APP"
  for _ in {1..30}; do
    pgrep -x MirrorLink >/dev/null 2>&1 && break
    sleep 0.1
  done
  if ! pgrep -x MirrorLink >/dev/null 2>&1; then
    print -u2 "应用未能在 3 秒内启动；请使用 --no-launch 保留构建包并检查系统日志。"
    exit 1
  fi
  if [[ "$SHOW_LOGS" == "1" ]]; then
    echo "==> 最近的镜连系统日志"
    /usr/bin/log show --style compact --last 15s --predicate 'process == "MirrorLink"' 2>/dev/null || true
  fi
else
  echo "==> 已跳过启动（--no-launch）"
fi
echo "$OUTPUT_APP"
