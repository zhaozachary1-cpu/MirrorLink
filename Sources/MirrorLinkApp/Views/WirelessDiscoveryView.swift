import SwiftUI
import AppKit

struct WirelessDiscoveryView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: WirelessConnectionStore
    let connectsDirectly: Bool
    var connectedSerials: Set<String> = []
    var knownHardwareNames: [String: String] = [:]
    var connectedDevices: [AndroidDevice] = []
    private var candidates: [WirelessService] {
        store.visibleServices.filter { !connectedSerials.contains($0.endpoint.address) && !connectedSerials.contains($0.adbSerial) }
    }

    var body: some View {
        let _ = language.selection
        if connectsDirectly {
            phoneRows
        } else {
          GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(connectsDirectly ? L10n.tr("附近开启无线调试的手机") : L10n.tr("发现的服务")).font(.headline)
                    Spacer()
                    if store.isDiscovering { ProgressView().controlSize(.small) }
                    Button(L10n.tr("刷新")) { store.discover() }
                        .disabled(store.isBusy || store.isDiscovering)
                }
                if candidates.isEmpty {
                    Label(store.isBusy ? L10n.tr("正在连接并确认手机状态…") : (store.discoveryMessage ?? (store.isDiscovering ? L10n.tr("正在发现手机…") : L10n.tr("暂未发现手机，请保持手机的无线调试开启。"))),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
                phoneRows
            }.padding(4)
          }
        }
    }

    private var phoneRows: some View {
        VStack(spacing: 12) {
                ForEach(candidates) { candidate in
                    let name = candidate.deviceName(knownHardwareNames: knownHardwareNames, connectedDevices: connectedDevices)
                    let title = name ?? (candidate.kind == .connection ? L10n.tr("Android 手机") : candidate.name)
                    HStack(spacing: 14) {
                        Image(systemName: "iphone").font(.title.weight(.light))
                            .foregroundStyle(.blue).frame(width: 32).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.headline).lineLimit(2).help(title + " · " + candidate.endpoint.address)
                            if candidate.kind == .connection && name == nil {
                                Text(L10n.tr("连接后显示品牌和型号"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if !connectsDirectly {
                                Text(candidate.endpoint.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                            } else if name != nil {
                                Text(L10n.tr("无线连接")).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if store.isBusy && store.connectionAddress == candidate.endpoint.address {
                            ProgressView().controlSize(.small)
                        }
                        Button {
                            if connectsDirectly { store.connectDiscovered(candidate) }
                            else { store.choose(candidate) }
                        } label: {
                            Text(connectsDirectly ? L10n.tr("开始投屏") : L10n.tr("使用此地址"))
                                .font(.body.weight(.semibold)).frame(minWidth: 104, minHeight: 28)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.blue)
                        .disabled(store.isBusy)
                        .accessibilityLabel(connectsDirectly
                            ? L10n.tr("连接并投屏 %@", title + " · " + candidate.endpoint.address)
                            : L10n.tr("使用此地址"))
                    }.padding(18)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
                }
        }
    }

    static func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }
}
