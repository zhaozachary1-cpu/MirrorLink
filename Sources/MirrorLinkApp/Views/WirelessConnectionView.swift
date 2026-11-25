import SwiftUI

/// Inline controls; discovery and cancellation belong to the main scene.
struct WirelessConnectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    @ObservedObject var sessions: MirrorSessionStore

    var body: some View {
        let _ = language.selection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.tr("无线连接"), systemImage: "wifi").font(.headline)
                    Spacer()
                    if store.mode != .nearby {
                        Button(L10n.tr("收起")) { store.selectMode(.nearby) }
                            .buttonStyle(.borderless)
                    }
                    Menu {
                        Button(L10n.tr("扫码配对")) { store.selectMode(.qr) }
                        Button(L10n.tr("手动连接")) { store.selectMode(.manual); store.step = .connection }
                        Button(L10n.tr("检查本地网络权限")) { WirelessDiscoveryView.openNetworkSettings() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(L10n.tr("更多无线连接方式"))
                }
                Text(L10n.tr("连接同一 Wi-Fi，并开启手机“无线调试”。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch store.mode {
                case .qr: WirelessQRPairingView(store: store.qr)
                case .nearby:
                    WirelessDiscoveryView(store: store, connectsDirectly: true, connectedSerials: Set(sessions.devices.filter { $0.state == .ready }.map(\.serial)))
                case .manual:
                    ManualWirelessConnectionView(store: store)
                }

                if store.mode != .qr, let message = store.message {
                    HStack(alignment: .top, spacing: 10) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        else { Image(systemName: store.isError ? "exclamationmark.triangle" : "info.circle") }
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(store.isError ? Color.orange : Color.primary)
                    .accessibilityElement(children: .combine)
                }

                if store.mode != .qr, store.isError {
                    HStack {
                        Button(L10n.tr("重试")) { store.connect() }.disabled(store.isBusy || store.connectionAddress.isEmpty)
                        Button(L10n.tr("扫码配对")) { store.selectMode(.qr) }.disabled(store.isBusy)
                    }
                }
            }
    }
}
