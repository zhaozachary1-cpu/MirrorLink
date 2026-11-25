import SwiftUI

struct WirelessQRPairingView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessQRPairingStore

    var body: some View {
        let _ = language.selection
        GroupBox {
            HStack(spacing: 20) {
                if let session = store.session {
                    if let image = WirelessQRCode.image(for: session) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none).resizable().scaledToFit()
                            .frame(width: 160, height: 160).padding(12)
                            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(L10n.tr("无线调试配对二维码，请用手机扫描"))
                    } else {
                        Label(L10n.tr("二维码无法生成，请重试或使用手动连接。"), systemImage: "exclamationmark.triangle")
                    }
                } else if store.phase.isActive {
                    Image(systemName: "wifi").font(.system(size: 48)).foregroundStyle(.secondary)
                        .frame(width: 184, height: 184)
                }

                VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("手机打开“无线调试”，选择“使用二维码配对设备”。"))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 10) {
                    if store.phase == .pairing || store.phase == .connecting { ProgressView().controlSize(.small) }
                    else { Image(systemName: store.phase == .completed ? "checkmark.circle.fill" : "info.circle") }
                    Text(store.phase == .waitingForScan ? L10n.tr("扫码后自动投屏") : store.message)
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(store.phase == .failed ? Color.orange : Color.primary)
                .accessibilityElement(children: .combine)
                HStack {
                    if store.canRetryConnection {
                        Button(L10n.tr("重试连接，无需扫码")) { store.retryConnection() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(store.phase == .completed ? L10n.tr("连接新手机") : L10n.tr("刷新二维码")) { store.start() }
                        .disabled(store.phase == .pairing || store.phase == .connecting)
                }
                }
            }.padding(8).frame(maxWidth: .infinity)
        }
    }
}
