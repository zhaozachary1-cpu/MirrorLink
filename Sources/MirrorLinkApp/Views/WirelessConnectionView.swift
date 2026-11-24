import AppKit
import Combine
import SwiftUI

private typealias WirelessViewState<Value> = SwiftUI.State<Value>

struct WirelessConnectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    @ObservedObject var sessions: MirrorSessionStore
    @WirelessViewState private var windowHandle = WirelessWindowHandle()

    var body: some View {
        let _ = language.selection
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.tr("无线连接"), systemImage: "wifi")
                    .font(.title2.weight(.semibold))
                Text(L10n.tr("连接同一 Wi-Fi，并开启手机“无线调试”。"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if store.mode != .nearby {
                        Button { store.selectMode(.nearby) } label: {
                            Label(L10n.tr("附近手机"), systemImage: "chevron.left")
                        }
                    } else {
                        Button(L10n.tr("连接新手机")) { store.selectMode(.qr) }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Menu(L10n.tr("更多")) {
                        Button(L10n.tr("手动连接")) { store.selectMode(.manual); store.step = .connection }
                        Button(L10n.tr("检查本地网络权限")) { WirelessDiscoveryView.openNetworkSettings() }
                    }
                }

                switch store.mode {
                case .qr: WirelessQRPairingView(store: store.qr)
                case .nearby:
                    WirelessDiscoveryView(store: store, connectsDirectly: true)
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
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 540)
        .background(SceneWindowReference { window in windowHandle.window = window })
        .onReceive(store.$connectedDeviceID.combineLatest(sessions.$sessionStates)) { deviceID, states in
            guard let deviceID, states[deviceID] == .mirroring else { return }
            windowHandle.window?.close()
        }
        .onAppear { store.open() }
        .onDisappear { store.close() }
    }
}

private final class WirelessWindowHandle {
    weak var window: NSWindow?
}
