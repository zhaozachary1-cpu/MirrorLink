import SwiftUI

struct WirelessQRPairingView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessQRPairingStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = language.selection
        GroupBox {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("无线调试 → 使用二维码配对设备"))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text(L10n.tr("使用手机的无线调试扫码入口。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)

                if let session = store.session {
                    if let image = WirelessQRCode.image(for: session) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none).resizable().scaledToFit()
                            .frame(width: 224, height: 224).padding(22)
                            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(L10n.tr("无线调试配对二维码，请用手机扫描"))
                    } else {
                        Label(L10n.tr("二维码无法生成，请重试或使用手动连接。"), systemImage: "exclamationmark.triangle")
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(L10n.tr("本次二维码 · %@ 秒后失效", String(max(0, Int(session.expiresAt.timeIntervalSince(context.date))))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else if store.phase.isActive {
                    Image(systemName: "wifi").font(.system(size: 48)).foregroundStyle(.secondary)
                        .frame(height: 110)
                }

                HStack(alignment: .top, spacing: 10) {
                    if store.phase.isActive { ProgressView().controlSize(.small) }
                    else { Image(systemName: store.phase == .completed ? "checkmark.circle.fill" : "info.circle") }
                    Text(store.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(store.phase == .failed ? Color.orange : Color.primary)
                .accessibilityElement(children: .combine)
                if store.phase == .failed, let warning = store.discoveryWarning {
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if store.canRetryConnection {
                        Button(L10n.tr("重试连接，无需扫码")) { store.retryConnection() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(store.phase == .completed ? L10n.tr("配对另一台手机") : L10n.tr("生成新二维码")) { store.start() }
                        .disabled(store.phase == .pairing || store.phase == .connecting)
                    if store.phase.isActive { Button(L10n.tr("停止")) { store.stop() } }
                    if store.phase == .failed {
                        Button(L10n.tr("本地网络权限")) { WirelessDiscoveryView.openNetworkSettings() }
                    }
                }
                if store.session != nil { Text(L10n.tr("二维码仅本次有效，请勿分享。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(12).frame(maxWidth: .infinity)
        }
    }
}
