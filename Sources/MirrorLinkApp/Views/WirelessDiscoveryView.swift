import SwiftUI
import AppKit

struct WirelessDiscoveryView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    let connectsDirectly: Bool

    var body: some View {
        let _ = language.selection
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(connectsDirectly ? L10n.tr("附近开启无线调试的手机") : L10n.tr("发现的服务")).font(.headline)
                    Spacer()
                    if store.isDiscovering { ProgressView().controlSize(.small) }
                    Button(L10n.tr("刷新")) { store.discover() }
                        .disabled(store.isBusy || store.isDiscovering)
                }
                Text(connectsDirectly
                     ? L10n.tr("此页每 4 秒自动发现一次。已授权此 Mac 的手机可直接连接；首次使用请先扫码。服务名由手机提供，请核对设备。")
                     : L10n.tr("选择地址填入上方，仍需核对手机显示的信息。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.visibleServices.isEmpty {
                    Label(store.isBusy ? L10n.tr("正在连接并确认手机状态…") : (store.discoveryMessage ?? (store.isDiscovering ? L10n.tr("正在发现手机…") : L10n.tr("暂未发现手机，请保持手机的无线调试开启。"))),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                    if connectsDirectly {
                        HStack {
                            Button(L10n.tr("首次使用：扫码配对")) { store.selectMode(.qr) }
                            Button(L10n.tr("使用地址连接")) { store.selectMode(.manual); store.step = .connection }
                        }
                        .disabled(store.isBusy)
                    }
                }
                ForEach(store.visibleServices) { candidate in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.radiowaves.left.and.right").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.name).font(.callout).lineLimit(1).help(candidate.name)
                            Text(candidate.endpoint.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(connectsDirectly ? L10n.tr("连接并投屏") : L10n.tr("使用此地址")) {
                            if connectsDirectly { store.connectDiscovered(candidate) }
                            else { store.choose(candidate) }
                        }
                        .disabled(store.isBusy)
                    }
                }
                Button(L10n.tr("检查本地网络权限")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }.padding(8)
        }
    }
}
