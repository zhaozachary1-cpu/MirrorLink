#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_BINARY="$ROOT_DIR/.build/mirrorlink-localization-checks"
mkdir -p "$ROOT_DIR/.build"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/localization_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AppLanguage.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AndroidDevice.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/MirrorQualityProfile.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/MirrorSessionState.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/MirrorVideoStatus.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/L10n.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Stores/LanguageStore.swift" \
  -o "$CHECK_BINARY"
MIRRORLINK_TEST_LANGUAGE=zh-Hans MIRRORLINK_LOCALIZATION_ROOT="$ROOT_DIR/Sources/MirrorLinkApp/Resources/Localizations" "$CHECK_BINARY" "$ROOT_DIR"
