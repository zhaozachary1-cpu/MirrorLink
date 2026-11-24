#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CHECK_DIR="$ROOT_DIR/.build/mirrorlink-wireless-checks"
mkdir -p "$CHECK_DIR"
swiftc -swift-version 5 \
  "$ROOT_DIR/script/wireless_checks.swift" \
  "$ROOT_DIR/script/wireless_qr_checks.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AppLanguage.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/L10n.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/AndroidDevice.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/WirelessEndpoint.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/WirelessService.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Models/WirelessQRSession.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBDeviceParser.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ADBDeviceIdentity.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/ToolPaths.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/WirelessADBService.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/BonjourWirelessDiscovery.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Services/LocalNetworkReadiness.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessRunner.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/ProcessCancellation.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Support/WirelessQRCode.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Stores/WirelessConnectionStore.swift" \
  "$ROOT_DIR/Sources/MirrorLinkApp/Stores/WirelessQRPairingStore.swift" \
  -o "$CHECK_DIR/wireless-checks"
MIRRORLINK_TEST_LANGUAGE=zh-Hans MIRRORLINK_LOCALIZATION_ROOT="$ROOT_DIR/Sources/MirrorLinkApp/Resources/Localizations" "$CHECK_DIR/wireless-checks"
