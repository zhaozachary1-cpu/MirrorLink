import SwiftUI

struct WirelessQRPairingView: View {
    @ObservedObject var store: WirelessQRPairingStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("用手机扫一扫，无需输入配对码").font(.headline)
                    Text("在手机打开：开发者选项 → 无线调试 → 使用二维码配对设备，然后扫描下方二维码。")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("请使用“无线调试”里的扫码入口，不是微信或普通相机。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)

                if let session = store.session {
                    if let image = WirelessQRCode.image(for: session) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none).resizable().scaledToFit()
                            .frame(width: 224, height: 224).padding(22)
                            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("无线调试配对二维码，请用手机扫描")
                    } else {
                        Label("二维码无法生成，请重试或使用手动连接。", systemImage: "exclamationmark.triangle")
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("本次二维码 · \(max(0, Int(session.expiresAt.timeIntervalSince(context.date)))) 秒后失效")
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
                if let warning = store.discoveryWarning {
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(store.phase == .completed ? "配对另一台手机" : "生成新二维码") { store.start() }
                        .disabled(store.phase == .pairing || store.phase == .connecting)
                    if store.phase.isActive { Button("停止") { store.stop() } }
                    if store.phase == .completed { Button("查看主窗口") { openWindow(id: "main") } }
                }
                Text("二维码是本次临时授权凭据，请勿分享或截图转发。关闭此窗口或切换方式会停止发现和自动投屏；已完成的手机授权不会因此撤销。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity)
        }
    }
}
