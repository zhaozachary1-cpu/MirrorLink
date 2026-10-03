#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
# Keep local release artifacts with this checkout, not in a separate home path.
# The checkout must stay outside File Provider-synced Documents/Desktop folders.
RELEASE_ROOT="${MIRRORLINK_RELEASE_DIR:-$ROOT_DIR/artifacts/Releases}"
SIGN_IDENTITY=""
NOTARIZE=0
COMMUNITY=0
CREATE_DMG=1
CREATE_ZIP=1
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

usage() {
  cat <<'EOF'
用法：
  ./script/package_release.sh [选项]

选项：
  --community        免费社区发行：ad-hoc 完整性签名，不申请 Apple 公证
  --sign <identity>   用指定的 Developer ID Application 身份签名
  --notarize          提交公证并将票据 stapler 到应用（必须已签名）
  --notary-profile <name> 使用 notarytool 已保存的钥匙串配置
  --no-dmg            不生成 DMG
  --no-zip            不生成 ZIP
  --output-dir <dir>  指定发行产物目录
  -h, --help          显示帮助

示例：
  ./script/package_release.sh
  ./script/package_release.sh --sign "Developer ID Application: Example, Inc. (TEAMID)"
  ./script/package_release.sh --sign "Developer ID Application: Example, Inc. (TEAMID)" --notary-profile mirrorlink-notary --notarize
EOF
}

while (( $# > 0 )); do
  argument="$1"
  shift
  case "$argument" in
    --community) COMMUNITY=1 ;;
    --sign)
      if (( $# == 0 )); then
        print -u2 -- "--sign 需要一个签名身份。"
        exit 2
      fi
      SIGN_IDENTITY="$1"
      shift
      ;;
    --notarize) NOTARIZE=1 ;;
    --notary-profile)
      if (( $# == 0 )); then
        print -u2 -- "--notary-profile 需要配置名称。"
        exit 2
      fi
      NOTARY_PROFILE="$1"
      shift
      ;;
    --no-dmg) CREATE_DMG=0 ;;
    --no-zip) CREATE_ZIP=0 ;;
    --output-dir)
      if (( $# == 0 )); then
        print -u2 -- "--output-dir 需要一个目录路径。"
        exit 2
      fi
      RELEASE_ROOT="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "未知参数：$argument"
      usage >&2
      exit 2
      ;;
  esac
done

# Preserve the caller's interpretation of a relative --output-dir/environment.
RELEASE_ROOT="${RELEASE_ROOT:A}"
cd "$ROOT_DIR"

if [[ "$COMMUNITY" == 1 && ( -n "$SIGN_IDENTITY" || "$NOTARIZE" == 1 ) ]]; then
  print -u2 -- '--community 不能与 Developer ID 或公证模式混用。'
  exit 2
fi

if [[ "$NOTARIZE" == "1" && -z "$SIGN_IDENTITY" ]]; then
  print -u2 -- "--notarize 必须与 --sign 一起使用。"
  exit 2
fi

if [[ "$NOTARIZE" == "1" && -z "$NOTARY_PROFILE" ]]; then
  print -u2 -- "--notarize 需要 --notary-profile，避免把 Apple 凭据暴露在命令行或环境变量中。"
  exit 2
fi

if [[ "$CREATE_DMG" == "1" && "$(uname -s)" != "Darwin" ]]; then
  print -u2 "DMG 只能在 macOS 上生成。"
  exit 2
fi

if [[ "$NOTARIZE" == "1" && ! -x "$(command -v xcrun 2>/dev/null || true)" ]]; then
  print -u2 -- "--notarize 需要安装 Xcode Command Line Tools 或 Xcode。"
  exit 2
fi

# Fail before compilation when a required identity/profile is unavailable.
if [[ -n "$SIGN_IDENTITY" ]]; then
  if [[ "$SIGN_IDENTITY" != "Developer ID Application: "* ]]; then
    print -u2 -- '--sign 必须是 Developer ID Application 身份。'
    exit 2
  fi
  if ! security find-identity -p codesigning -v | grep -Fq "\"$SIGN_IDENTITY\""; then
    print -u2 "钥匙串没有可用的证书及对应私钥：$SIGN_IDENTITY"
    exit 2
  fi
fi
if [[ "$NOTARIZE" == "1" ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null
fi

# Public binaries carry matching notices and an accompanying source archive.
# The default local preview remains an offline packaging path.
if [[ "$COMMUNITY" == 1 || -n "$SIGN_IDENTITY" ]]; then
  "$ROOT_DIR/script/prepare_third_party.sh"
fi

BUILD_ID="$(date -u +%Y%m%d-%H%M%S)"
TEMP_BASE="$ROOT_DIR/work/tmp"
mkdir -p "$TEMP_BASE"
TEMP_ROOT="$(mktemp -d "$TEMP_BASE/mirrorlink-release.XXXXXX")"
cleanup_release_temp() {
  if [[ -n "${TEMP_ROOT:-}" && -d "$TEMP_ROOT" && ! -L "$TEMP_ROOT" && "$TEMP_ROOT" == "$TEMP_BASE"/mirrorlink-release.* ]]; then
    rm -rf -- "$TEMP_ROOT"
  fi
}
trap cleanup_release_temp EXIT

BUILD_OUTPUT="$TEMP_ROOT/builds"
mkdir -p "$BUILD_OUTPUT"

echo "==> 构建 universal 应用"
"$ROOT_DIR/script/build_and_run.sh" --verify --no-launch --output-dir "$BUILD_OUTPUT"

BUILT_APP="$(find "$BUILD_OUTPUT" -maxdepth 1 -type d -name '*.app' -print | sort | tail -1)"
if [[ -z "$BUILT_APP" || ! -d "$BUILT_APP" ]]; then
  print -u2 "没有找到构建出的 .app。"
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$BUILT_APP/Contents/Info.plist")"
PACKAGE_ROOT="$RELEASE_ROOT/MirrorLink-$VERSION-$BUILD_ID"
APP_PATH="$PACKAGE_ROOT/MirrorLink.app"
SHARE_STAGE="$TEMP_ROOT/MirrorLink-$VERSION-macOS-universal"
mkdir -p "$PACKAGE_ROOT" "$SHARE_STAGE"
ditto "$BUILT_APP" "$APP_PATH"
# Clean only copy-added Finder metadata on this generated bundle root.
# Preserve quarantine and every other extended attribute.
xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true

SIGNING_STATUS="local-adhoc"
DISTRIBUTION="local-preview"
if [[ -n "$SIGN_IDENTITY" ]]; then
  # This value is part of the sealed bundle, so set it before signing.
  plutil -replace MirrorLinkDistributionChannel -string "developer-id" "$APP_PATH/Contents/Info.plist"
  echo "==> 使用签名身份：$SIGN_IDENTITY"
  "$ROOT_DIR/script/sign_bundle.sh" "$APP_PATH" "$SIGN_IDENTITY"
  SIGNING_STATUS="developer-id"
  DISTRIBUTION="developer-id"
elif [[ "$COMMUNITY" == 1 ]]; then
  DISTRIBUTION="community"
  plutil -replace MirrorLinkDistributionChannel -string "$DISTRIBUTION" "$APP_PATH/Contents/Info.plist"
  "$ROOT_DIR/script/sign_bundle.sh" "$APP_PATH" -
  echo '==> 免费社区版：未公证，首次安装可能需要用户手动允许打开'
else
  echo "==> 未提供 Developer ID，保留本地 ad-hoc 发行包"
fi

echo "==> 校验应用包结构"
plutil -lint "$APP_PATH/Contents/Info.plist"
test -x "$APP_PATH/Contents/MacOS/MirrorLink"
test -x "$APP_PATH/Contents/MacOS/adb"
test -x "$APP_PATH/Contents/MacOS/scrcpy"
test -f "$APP_PATH/Contents/Resources/scrcpy-server"
for binary in \
  "$APP_PATH/Contents/MacOS/MirrorLink" \
  "$APP_PATH/Contents/MacOS/adb" \
  "$APP_PATH/Contents/MacOS/scrcpy"; do
  lipo -verify_arch arm64 "$binary"
  lipo -verify_arch x86_64 "$binary"
done

# Both local and Developer ID builds must have a valid sealed bundle. This
# verifies integrity only; it is not a Gatekeeper or notarization acceptance.
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv --entitlements :- "$APP_PATH" 2>&1 | sed -n '1,32p'

mkdir -p "$SHARE_STAGE"
ln -s /Applications "$SHARE_STAGE/Applications"
ditto "$APP_PATH" "$SHARE_STAGE/MirrorLink.app"
xattr -d com.apple.FinderInfo "$SHARE_STAGE/MirrorLink.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$SHARE_STAGE/MirrorLink.app"
cp "$ROOT_DIR/README.md" "$SHARE_STAGE/README.md"
cp "$ROOT_DIR/DISTRIBUTION.md" "$SHARE_STAGE/DISTRIBUTION.md"
cp "$ROOT_DIR/LICENSE" "$SHARE_STAGE/LICENSE"
cp "$ROOT_DIR/NOTICE" "$SHARE_STAGE/NOTICE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$SHARE_STAGE/THIRD_PARTY_NOTICES.md"

make_zip() {
  local output_path="$1"
  ditto -c -k --sequesterRsrc --keepParent "$SHARE_STAGE" "$output_path"
}

make_dmg() {
  local output_path="$1"
  hdiutil create -volname "镜连" -srcfolder "$SHARE_STAGE" -ov -format UDZO "$output_path" >/dev/null
}

ZIP_PATH="$PACKAGE_ROOT/MirrorLink-$VERSION-macOS-universal.zip"
DMG_PATH="$PACKAGE_ROOT/MirrorLink-$VERSION-macOS-universal.dmg"
UPDATE_DIR="$PACKAGE_ROOT/updates"

notarize_artifact() {
  local artifact="$1" label="$2"
  local result="$PACKAGE_ROOT/notary-$label-result.json"
  # Keep evidence even on rejection/network failure; do not write credentials.
  local submit_status=0
  if xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json | tee "$result"; then
    :
  else
    submit_status=$?
  fi
  local submission_id
  submission_id="$(plutil -extract id raw "$result" 2>/dev/null || true)"
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" "$PACKAGE_ROOT/notary-$label-log.json" || true
  fi
  if [[ "$submit_status" != 0 || "$(plutil -extract status raw "$result" 2>/dev/null || true)" != Accepted ]]; then
    print -u2 "Apple 公证未通过；诊断保留在 $PACKAGE_ROOT"
    exit 1
  fi
}

if [[ "$CREATE_ZIP" == "1" ]]; then
  echo "==> 生成 ZIP"
  make_zip "$ZIP_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  NOTARY_ZIP="$ZIP_PATH"
  if [[ "$CREATE_ZIP" != "1" ]]; then
    NOTARY_ZIP="$TEMP_ROOT/MirrorLink-notary.zip"
  fi
  echo "==> 提交 Apple 公证"
  make_zip "$NOTARY_ZIP"
  notarize_artifact "$NOTARY_ZIP" app
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  ditto "$APP_PATH" "$SHARE_STAGE/MirrorLink.app"
  xattr -d com.apple.FinderInfo "$SHARE_STAGE/MirrorLink.app" 2>/dev/null || true
  codesign --verify --deep --strict --verbose=2 "$SHARE_STAGE/MirrorLink.app"
  [[ "$CREATE_ZIP" == "1" ]] && make_zip "$ZIP_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  spctl -a -vv --type execute "$APP_PATH"
fi

if [[ "$CREATE_DMG" == "1" ]]; then
  echo "==> 生成 DMG"
  make_dmg "$DMG_PATH"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
  fi
  if [[ "$NOTARIZE" == "1" ]]; then
    notarize_artifact "$DMG_PATH" dmg
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi
fi

# Sparkle receives exactly one .app, without the drag-to-Applications symlink.
mkdir -p "$UPDATE_DIR"
UPDATE_ZIP="$UPDATE_DIR/MirrorLink-$VERSION-update.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UPDATE_ZIP"

SOURCE_ARCHIVE=""
if [[ "$DISTRIBUTION" != local-preview ]]; then
  SOURCE_NAME="MirrorLink-$VERSION-third-party-sources"
  SOURCE_STAGE="$TEMP_ROOT/$SOURCE_NAME"
  mkdir -p "$SOURCE_STAGE/sources" "$SOURCE_STAGE/licenses"
  while read -r kind filename digest url; do
    [[ "$kind" == source ]] || continue
    cp "$ROOT_DIR/work/community-sources/$filename" "$SOURCE_STAGE/sources/$filename"
  done < "$ROOT_DIR/vendor/third-party-sources.tsv"
  ditto "$ROOT_DIR/vendor/licenses" "$SOURCE_STAGE/licenses"
  cp "$ROOT_DIR/vendor/third-party-sources.tsv" "$SOURCE_STAGE/third-party-sources.tsv"
  cp "$ROOT_DIR/vendor/licenses/README.md" "$SOURCE_STAGE/README.md"
  cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$SOURCE_STAGE/THIRD_PARTY_NOTICES.md"
  SOURCE_ARCHIVE="$PACKAGE_ROOT/$SOURCE_NAME.tar.gz"
  COPYFILE_DISABLE=1 tar -czf "$SOURCE_ARCHIVE" -C "$TEMP_ROOT" "$SOURCE_NAME"
fi

# This public checksum list contains only filenames, never local paths.
(
  cd "$PACKAGE_ROOT"
  [[ -f "${ZIP_PATH:t}" ]] && shasum -a 256 "${ZIP_PATH:t}"
  [[ -f "${DMG_PATH:t}" ]] && shasum -a 256 "${DMG_PATH:t}"
  [[ -n "$SOURCE_ARCHIVE" ]] && shasum -a 256 "${SOURCE_ARCHIVE:t}"
  cd updates
  shasum -a 256 "${UPDATE_ZIP:t}"
) > "$PACKAGE_ROOT/SHA256SUMS.txt"

MANIFEST="$PACKAGE_ROOT/RELEASE-MANIFEST.txt"
{
  echo "MirrorLink release manifest"
  echo "version=$VERSION"
  echo "bundle_version=$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")"
  echo "build_id=$BUILD_ID"
  echo "architecture=arm64+x86_64"
  echo "signing=$SIGNING_STATUS"
  echo "distribution=$DISTRIBUTION"
  echo "notarized=$([[ "$NOTARIZE" == "1" ]] && echo yes || echo no)"
  echo "app=$APP_PATH"
  echo "update_zip=$UPDATE_ZIP"
  [[ -n "$SOURCE_ARCHIVE" ]] && echo "third_party_sources=$SOURCE_ARCHIVE"
  if [[ -f "$ZIP_PATH" ]]; then echo "zip=$ZIP_PATH"; fi
  if [[ -f "$DMG_PATH" ]]; then echo "dmg=$DMG_PATH"; fi
  echo
  echo "SHA-256"
  shasum -a 256 "$APP_PATH/Contents/MacOS/MirrorLink"
  shasum -a 256 "$APP_PATH/Contents/MacOS/adb"
  shasum -a 256 "$APP_PATH/Contents/MacOS/scrcpy"
  shasum -a 256 "$APP_PATH/Contents/Resources/scrcpy-server"
  shasum -a 256 "$APP_PATH/Contents/Resources/AppIcon.icns"
  [[ -f "$ZIP_PATH" ]] && shasum -a 256 "$ZIP_PATH"
  [[ -f "$DMG_PATH" ]] && shasum -a 256 "$DMG_PATH"
  shasum -a 256 "$UPDATE_ZIP"
  [[ -n "$SOURCE_ARCHIVE" ]] && shasum -a 256 "$SOURCE_ARCHIVE"
  :
} > "$MANIFEST"

echo "==> 发行包已生成"
echo "$PACKAGE_ROOT"
echo "签名状态：$SIGNING_STATUS"
if [[ "$DISTRIBUTION" == "community" ]]; then
  echo '社区版未经过 Apple 公证。必须生成签名更新清单、核对第三方材料后方可公开上传。'
elif [[ "$SIGNING_STATUS" != "developer-id" ]]; then
  echo "注意：这是本地 ad-hoc 包，适合本机验证，不保证其他用户通过 Gatekeeper。"
fi
