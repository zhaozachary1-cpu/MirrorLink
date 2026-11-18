#!/bin/zsh
# One inside-out signing policy shared by development and release packaging.
set -euo pipefail
if (( $# != 2 )); then
  print -u2 '用法：script/sign_bundle.sh <MirrorLink.app> <identity 或 ->'
  exit 2
fi
APP_PATH="${1:A}"
IDENTITY="$2"
[[ -d "$APP_PATH/Contents" ]] || exit 2
[[ "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" == com.mirrorlink.desktop ]] || exit 2
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
[[ -f "$FRAMEWORK/Versions/B/Sparkle" ]] || { print -u2 '缺少 Sparkle.framework'; exit 2; }
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
# Sign executable leaves before containers; never use --deep for signing.
# Preserve the entitlements from the pinned upstream Sparkle distribution.
for component in \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
  "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
  "$FRAMEWORK/Versions/B/Updater.app" \
  "$FRAMEWORK/Versions/B/Autoupdate" \
  "$FRAMEWORK"; do
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$component"
done
PHONE_APP="$APP_PATH/Contents/Helpers/MirrorLinkWindow.app"
if [[ -d "$PHONE_APP" ]]; then
  codesign "${SIGN_ARGS[@]}" "$PHONE_APP/Contents/MacOS/scrcpy"
  codesign "${SIGN_ARGS[@]}" "$PHONE_APP"
else
  codesign "${SIGN_ARGS[@]}" "$APP_PATH/Contents/MacOS/scrcpy"
fi
for executable in adb MirrorLink; do
  codesign "${SIGN_ARGS[@]}" "$APP_PATH/Contents/MacOS/$executable"
done
codesign "${SIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
