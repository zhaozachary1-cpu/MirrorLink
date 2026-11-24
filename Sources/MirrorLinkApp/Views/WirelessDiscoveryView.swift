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
                if store.visibleServices.isEmpty {
                    Label(store.isBusy ? L10n.tr("正在连接并确认手机状态…") : (store.discoveryMessage ?? (store.isDiscovering ? L10n.tr("正在发现手机…") : L10n.tr("暂未发现手机，请保持手机的无线调试开启。"))),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                    if connectsDirectly {
                        Text(L10n.tr("首次使用？点击“连接新手机”扫码授权。"))
                            .font(.caption).foregroundStyle(.secondary)
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
                        .accessibilityLabel(L10n.tr("连接并投屏 %@", candidate.name))
                    }
                }
            }.padding(8)
        }
    }

    static func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }
}
