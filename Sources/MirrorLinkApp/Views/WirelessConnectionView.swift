import SwiftUI

struct WirelessConnectionView: View {
    @ObservedObject var store: WirelessConnectionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("无线连接 Android 手机", systemImage: "wifi")
                    .font(.title2.weight(.semibold))
                Text("无需插线。手机与 Mac 连接同一 Wi-Fi，在手机“开发者选项”中打开“无线调试”。需要 Android 11 或更高版本且系统支持无线调试。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("连接步骤", selection: $store.step) {
                    ForEach(WirelessConnectionStep.allCases, id: \.self) { step in
                        Text(step.rawValue).tag(step)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(store.isBusy)

                GroupBox(store.step == .pairing ? "1. 使用手机配对码授权此 Mac" : "2. 连接并开始投屏") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(store.step == .pairing
                            ? "在手机点“使用配对码配对设备”，保持弹窗打开。填写弹窗里的 IP 地址、端口和配对码。"
                            : "已配对的手机可以直接使用这一步。返回手机“无线调试”主页面，填写该页的“IP 地址和端口”。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if store.step == .pairing {
                            LabeledContent("配对地址") {
                                TextField("例如 192.168.1.8:37123", text: $store.pairingAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("配对地址")
                            }
                            LabeledContent("6 位配对码") {
                                SecureField("仅用于本次配对", text: $store.pairingCode)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("6 位配对码")
                                    .onSubmit { store.pair() }
                            }
                            Button("配对手机") { store.pair() }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.pairingAddress.isEmpty || store.pairingCode.isEmpty)
                        } else {
                            LabeledContent("连接地址") {
                                TextField("例如 192.168.1.8:39847", text: $store.connectionAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("连接地址")
                                    .onSubmit { store.connect() }
                            }
                            Label("连接端口 ≠ 配对端口。切换网络后请重新查看手机上的地址。", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("连接并投屏") { store.connect() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(store.connectionAddress.isEmpty)
                                Button("查看主窗口") { openWindow(id: "main") }
                            }
                        }
                    }
                    .padding(6)
                    .disabled(store.isBusy)
                }

                if let message = store.message {
                    HStack(alignment: .top, spacing: 10) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        else { Image(systemName: store.isError ? "exclamationmark.triangle" : "checkmark.circle") }
                        Text(message)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(store.isError ? Color.orange : Color.primary)
                    .accessibilityElement(children: .combine)
                }

                discovery

                Text("仅在可信网络使用无线调试。系统询问本地网络访问时请允许镜连。访客 Wi-Fi、设备隔离或 VPN 可能阻止连接。用完可在主窗口停止投屏，并在手机关闭无线调试；这不会修改其他手机的连接。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("没有“无线调试”选项的手机请继续使用 USB。配对码不保存；ADB 会使用自己的系统级配对凭据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 620, idealHeight: 720)
        .onAppear { store.discover() }
        .onDisappear { store.clearSecret() }
    }

    private var discovery: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.step == .pairing ? "发现的配对服务" : "发现的连接服务")
                        .font(.headline)
                    Spacer()
                    if store.isDiscovering { ProgressView().controlSize(.small) }
                    Button("发现手机") { store.discover() }
                        .disabled(store.isBusy || store.isDiscovering)
                }
                Text("点击地址可填入上方。只显示局域网广播，不代表已获得手机授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.visibleServices.isEmpty {
                    Text(store.discoveryMessage ?? (store.isDiscovering ? "正在发现…" : "当前没有这一步的服务；可手动输入手机显示的地址。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.visibleServices) { service in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.endpoint.address).font(.callout.monospaced())
                            Text(service.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("使用此地址") { store.choose(service) }
                            .disabled(store.isBusy)
                    }
                }
            }
            .padding(6)
        }
    }
}
