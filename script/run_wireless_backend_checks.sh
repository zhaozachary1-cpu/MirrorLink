#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_DIR="$ROOT_DIR/.build/mirrorlink-backend-checks"
mkdir -p "$CHECK_DIR"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/wireless_backend_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/WirelessDebugBackend.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ToolPaths.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessRunner.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessCancellation.swift" \
  -o "$CHECK_DIR/backend-checks"
"$CHECK_DIR/backend-checks" "$ROOT_DIR/vendor/platform-tools/adb"
