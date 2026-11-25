import SwiftUI

/// Inline controls; discovery and cancellation belong to the main scene.
struct WirelessConnectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    @ObservedObject var sessions: MirrorSessionStore

    private var knownHardwareNames: [String: String] {
        Dictionary(uniqueKeysWithValues: sessions.knownDevices.compactMap { device in
            guard device.id.hasPrefix("hardware:"), !device.model.isEmpty else { return nil }
            return (String(device.id.dropFirst("hardware:".count)), device.model)
        })
    }

    var body: some View {
        let _ = language.selection
            VStack(alignment: .leading, spacing: 16) {
                if store.mode != .nearby {
                    HStack {
                        Text(L10n.tr("连接新手机")).font(.headline)
                        Spacer()
                        Button(L10n.tr("返回")) { store.selectMode(.nearby) }.buttonStyle(.borderless)
                    }
                }
                switch store.mode {
                case .qr: WirelessQRPairingView(store: store.qr)
                case .nearby:
                    WirelessDiscoveryView(store: store, connectsDirectly: true,
                        connectedSerials: Set(sessions.devices.filter { $0.state == .ready }.map(\.serial)),
                        knownHardwareNames: knownHardwareNames, connectedDevices: sessions.devices)
                    if sessions.displayedDevices.isEmpty && store.visibleServices.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "iphone").font(.system(size: 44, weight: .light)).foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text(L10n.tr("插上数据线，或无线连接手机。"))
                                .font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    if sessions.displayedDevices.isEmpty && store.visibleServices.isEmpty {
                        newPhoneButton.buttonStyle(.borderedProminent)
                    } else {
                        newPhoneButton.buttonStyle(.bordered)
                    }
                case .manual:
                    ManualWirelessConnectionView(store: store, knownHardwareNames: knownHardwareNames, connectedDevices: sessions.devices)
                }

                if store.mode != .nearby {
                    Menu(L10n.tr("其他连接方式")) {
                        Button(L10n.tr("扫码连接")) { store.selectMode(.qr) }
                        Button(L10n.tr("手动连接")) { store.selectMode(.manual); store.step = .connection }
                        Button(L10n.tr("本地网络权限")) { WirelessDiscoveryView.openNetworkSettings() }
                    }.menuStyle(.borderlessButton).fixedSize().font(.caption)
                }

                if store.mode != .qr, let message = store.message, store.isBusy || store.isError {
                    HStack(alignment: .top, spacing: 10) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        else { Image(systemName: store.isError ? "exclamationmark.triangle" : "info.circle") }
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(store.isError ? Color.orange : Color.primary)
                    .accessibilityElement(children: .combine)
                }

                if store.mode == .nearby && store.isBusy {
                    Button(L10n.tr("取消")) { store.selectMode(.nearby) }.buttonStyle(.borderless)
                }
                if store.mode != .qr, store.isError, store.mode == .manual || store.visibleServices.isEmpty {
                    HStack {
                        Button(L10n.tr("重试")) { store.connect() }.disabled(store.isBusy || store.connectionAddress.isEmpty)
                    }
                }
            }
    }

    private var newPhoneButton: some View {
        Button { store.selectMode(.qr) } label: {
            Label(L10n.tr("连接新手机"), systemImage: "plus")
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28)
        }
        .controlSize(.large).disabled(!sessions.toolchainAvailable || store.isBusy)
    }
}
