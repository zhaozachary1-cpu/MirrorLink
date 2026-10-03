import SwiftUI

struct WirelessConnectionView: View {
    @ObservedObject var store: WirelessConnectionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("无线连接 Android 手机", systemImage: "wifi")
                    .font(.title2.weight(.semibold))
                Text("手机与 Mac 连接同一 Wi-Fi。在手机“开发者选项”中开启“无线调试”（Android 11+）。首次扫码授权，以后可发现并连接。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("连接方式", selection: Binding(get: { store.mode }, set: { store.selectMode($0) })) {
                    ForEach(WirelessConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

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

                Text("仅在可信网络使用。若系统询问，请允许镜连访问本地网络；访客 Wi-Fi、设备隔离或 VPN 可能阻止发现。用完可在手机关闭无线调试。发现手机不代表获得授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .frame(minWidth: 580, minHeight: 620)
        .onAppear { store.open() }
        .onDisappear { store.close() }
    }
}
