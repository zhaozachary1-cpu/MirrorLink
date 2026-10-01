#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
mkdir -p "$ROOT_DIR/.build"
CHECK_BINARY="$ROOT_DIR/.build/mirrorlink-update-checks"
swiftc -swift-version 5 "$ROOT_DIR/script/update_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/UpdateConfiguration.swift" -o "$CHECK_BINARY"
"$CHECK_BINARY"
