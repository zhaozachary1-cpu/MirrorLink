import SwiftUI

struct ManualWirelessConnectionView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("手机不支持扫码，或网络无法发现设备时，可使用此兼容入口。"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(L10n.tr("手动连接步骤"), selection: $store.step) {
                ForEach(WirelessConnectionStep.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(store.isBusy)
            GroupBox(store.step == .pairing ? L10n.tr("1. 使用手机配对码授权此 Mac") : L10n.tr("2. 连接并开始投屏")) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.step == .pairing
                         ? L10n.tr("在手机点“使用配对码配对设备”，保持弹窗打开。填写弹窗里的 IP 地址、端口和配对码。")
                         : L10n.tr("返回手机“无线调试”主页面，填写该页的“IP 地址和端口”。已配对的手机可直接连接。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.step == .pairing {
                        LabeledContent(L10n.tr("配对地址")) {
                            TextField(L10n.tr("例如 192.168.1.8:37123"), text: $store.pairingAddress)
                                .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.tr("配对地址"))
                        }
                        LabeledContent(L10n.tr("6 位配对码")) {
                            SecureField(L10n.tr("仅用于本次配对"), text: $store.pairingCode)
                                .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.tr("6 位配对码"))
                                .onSubmit { store.pair() }
                        }
                        Button(L10n.tr("配对手机")) { store.pair() }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.pairingAddress.isEmpty || store.pairingCode.isEmpty)
                    } else {
                        LabeledContent(L10n.tr("连接地址")) {
                            TextField(L10n.tr("例如 192.168.1.8:39847"), text: $store.connectionAddress)
                                .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.tr("连接地址"))
                                .onSubmit { store.connect() }
                        }
                        Label(L10n.tr("连接端口 ≠ 配对端口；切换网络后请重新查看。"), systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L10n.tr("连接并投屏")) { store.connect() }
                                .buttonStyle(.borderedProminent).disabled(store.connectionAddress.isEmpty)
                            Button(L10n.tr("查看主窗口")) { openWindow(id: "main") }
                        }
                    }
                }.padding(8).disabled(store.isBusy)
            }
            WirelessDiscoveryView(store: store, connectsDirectly: false)
        }
    }
}
