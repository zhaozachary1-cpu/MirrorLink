#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
SDL_INCLUDE="$ROOT_DIR/work/native-runtime/install/$(uname -m)/include"
[[ -f "$SDL_INCLUDE/SDL3/SDL.h" ]] || { print -u2 'Run script/build_scrcpy.sh first to prepare the pinned SDL headers.'; exit 2; }
CHECK_DIR="$(mktemp -d "$ROOT_DIR/work/tmp/native-toolbar-checks.XXXXXX")"
cp "$ROOT_DIR/vendor/mirror-window/MirrorWindowToolbar.h" "$CHECK_DIR/mirrorlink_toolbar.h"
clang -fobjc-arc -fblocks -Wno-deprecated-declarations -framework Cocoa \
  -I "$CHECK_DIR" -I "$SDL_INCLUDE" "$ROOT_DIR/script/native_toolbar_checks.m" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
