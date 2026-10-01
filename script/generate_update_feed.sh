#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
if (( $# < 2 || $# > 3 )); then
  print -u2 '用法：script/generate_update_feed.sh <发行目录> <HTTPS 下载 URL 前缀> [--allow-local-test]'
  exit 2
fi
RELEASE_DIR="${1:A}"
DOWNLOAD_PREFIX="$2"
ALLOW_LOCAL=0
if (( $# == 3 )); then
  [[ "$3" == --allow-local-test ]] || exit 2
  ALLOW_LOCAL=1
fi
[[ "$DOWNLOAD_PREFIX" == https://* && "$DOWNLOAD_PREFIX" != *'@'* && "$DOWNLOAD_PREFIX" != *'#'* && "$DOWNLOAD_PREFIX" != *'?'* ]] || { print -u2 '需要不含凭据、查询或片段的 HTTPS 下载前缀'; exit 2; }
[[ "$DOWNLOAD_PREFIX" == */ ]] || DOWNLOAD_PREFIX="$DOWNLOAD_PREFIX/"
APP_PATH="$RELEASE_DIR/MirrorLink.app"
UPDATE_DIR="$RELEASE_DIR/updates"
MANIFEST="$RELEASE_DIR/RELEASE-MANIFEST.txt"
[[ -f "$MANIFEST" && -d "$APP_PATH" && -d "$UPDATE_DIR" ]] || { print -u2 '发行目录不完整'; exit 2; }
if [[ "$ALLOW_LOCAL" == 0 ]]; then
  grep -qx 'signing=developer-id' "$MANIFEST"
  grep -qx 'notarized=yes' "$MANIFEST"
  codesign --verify --deep --strict "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl -a -vv --type execute "$APP_PATH"
else
  print -u2 '仅生成本地测试更新源；不代表正式公证发行，不会上传。'
fi
TOOLS="$ROOT_DIR/.build-mirrorlink-arm64/artifacts/sparkle/Sparkle/bin"
ACCOUNT=com.mirrorlink.desktop.updates
EXPECTED_KEY="$(plutil -extract SUPublicEDKey raw "$APP_PATH/Contents/Info.plist")"
ACTUAL_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
[[ "$EXPECTED_KEY" == "$ACTUAL_KEY" ]] || { print -u2 '钥匙串更新密钥与应用公钥不匹配；已停止'; exit 2; }
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --maximum-versions 3 \
  --embed-release-notes --download-url-prefix "$DOWNLOAD_PREFIX" "$UPDATE_DIR"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$UPDATE_DIR/appcast.xml"
echo "已生成并验证：$UPDATE_DIR/appcast.xml"
echo '发布时须同时上传 updates 中的 ZIP 与完整签名 XML；不要修改签名后的 XML。'
