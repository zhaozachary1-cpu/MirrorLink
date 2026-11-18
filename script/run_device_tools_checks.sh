#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_DIR="$ROOT_DIR/.build/mirrorlink-device-tools-checks"
mkdir -p "$CHECK_DIR"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/device_tools_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AppLanguage.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/L10n.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AndroidDevice.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/DeviceHealthReport.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/FeedbackReport.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ToolPaths.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessCancellation.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/BoundedProcessRunner.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ToolFileSafety.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/DeviceToolsService.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/FeedbackExportService.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Stores/DeviceToolsStore.swift" \
  -o "$CHECK_DIR/device-tools-checks"
MIRRORLINK_TEST_ROOT="$ROOT_DIR/work/tmp" MIRRORLINK_TEST_LANGUAGE=zh-Hans \
MIRRORLINK_LOCALIZATION_ROOT="$ROOT_DIR/Sources/MirrorLinkApp/Resources/Localizations" "$CHECK_DIR/device-tools-checks"
