#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_BINARY="$ROOT_DIR/.build/mirrorlink-core-checks"
mkdir -p "$ROOT_DIR/.build"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/core_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AndroidDevice.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBDeviceParser.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ToolPaths.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ScrcpyCommand.swift" \
  -o "$CHECK_BINARY"
"$CHECK_BINARY"
