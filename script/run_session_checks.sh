#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_DIR="$ROOT_DIR/.build/mirrorlink-session-checks"
mkdir -p "$CHECK_DIR"
swiftc -swift-version 5 "$ROOT_DIR/script/mock_scrcpy.swift" -o "$CHECK_DIR/mock-scrcpy"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/session_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AndroidDevice.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/MirrorSessionState.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBDeviceParser.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBDeviceIdentity.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBService.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ToolPaths.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ScrcpyCommand.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessRunner.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessCancellation.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Stores/MirrorSessionStore.swift" \
  -o "$CHECK_DIR/session-checks"
"$CHECK_DIR/session-checks" "$CHECK_DIR/mock-scrcpy"
