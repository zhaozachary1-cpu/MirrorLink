import SwiftUI

struct DetailView: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView(store: store)

                if store.selectedDevices.isEmpty {
                    EmptySelectionCard(store: store)
                } else {
                    SelectedDevicesCard(store: store)
                }

                StatusCard(store: store)

                if !store.displayedDevices.isEmpty {
                    DeviceSessionsCard(store: store)
                }

                if !store.toolchainAvailable {
                    ToolchainMissingCard()
                }

                LogCard(store: store)
            }
            .padding(28)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .background(.regularMaterial)
    }
}

private struct HeaderView: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.gradient)
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text("镜连")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("把多台 Android 手机画面同时投到 Mac 上")
                    .foregroundStyle(.secondary)
                Text("USB 或同一 Wi-Fi 连接 → 手机授权 → 多设备独立投屏")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let lastRefresh = store.lastRefresh {
                Text(lastRefresh, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("最近一次设备扫描时间")
            }
        }
    }
}

private struct SelectedDevicesCard: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已选择 \(store.selectedDevices.count) 台设备")
                            .font(.title3.weight(.semibold))
                        Text("其中 \(store.startableSelectedCount) 台可以开始投屏。每台手机拥有独立窗口，已启动的设备不会重复打开。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除选择") { store.clearDeviceSelection() }
                        .buttonStyle(.borderless)
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        store.startMirroring()
                    } label: {
                        Label("开始所选投屏", systemImage: "play.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStart)

                    Button(role: .destructive) {
                        store.stopMirroring()
                    } label: {
                        Label("停止全部", systemImage: "stop.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.isMirroring)

                    Spacer()
                    Text("取消勾选不会停止投屏")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(4)
        }
    }
}

private struct DeviceSessionsCard: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        GroupBox("设备与投屏") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.displayedDevices) { device in
                    DeviceSessionRow(device: device, store: store)
                    if device.id != store.displayedDevices.last?.id { Divider() }
                }
            }
            .padding(4)
        }
    }
}

private struct DeviceSessionRow: View {
    let device: AndroidDevice
    @ObservedObject var store: MirrorSessionStore

    private var state: MirrorSessionState {
        store.sessionState(for: device)
    }

    private var connection: AndroidDevice? { store.connectedDevice(for: device.id) }

    private var guidance: String? {
        if device.isWireless {
            guard let connection else { return "无线连接已断开。请确认同一 Wi-Fi 和无线调试，点击“无线连接”填写手机当前的连接端口。" }
            return connection.state == .ready ? nil : "无线设备尚未就绪。请检查无线调试授权与当前连接端口，必要时重新配对。"
        }
        guard let connection else {
            return "设备已断开。请检查 USB 连接，重新连接后可再次开始投屏。"
        }
        switch connection.state {
        case .ready: return nil
        case .unauthorized: return "请解锁这台手机，在“允许 USB 调试”提示中允许此电脑。"
        case .offline: return "设备处于离线状态。请解锁手机并重新插拔数据线，然后刷新设备。"
        case .unknown: return "无法确认设备状态。请检查数据线、USB 调试与手机授权后刷新。"
        }
    }

    private var statusTitle: String {
        if state == .idle { return connection?.state.title ?? "已断开" }
        return state.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: state.symbolName)
                    .foregroundStyle(stateTint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.callout.weight(.medium))
                    Text("\(device.transport) · \(device.serial)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(stateTint)
                if store.isMirroring(for: device.id) {
                    Button("停止") { store.stopMirroring(for: device.id) }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(state == .stopping)
                        .help("只停止 \(device.logLabel) 的投屏")
                } else {
                    Button(state.isFailure ? "重试" : "开始") { store.startMirroring(for: device.id) }
                        .buttonStyle(.bordered)
                        .disabled(!store.canStart(for: device.id))
                }
            }
            if case let .failed(message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var stateTint: Color {
        switch state {
        case .idle: return .secondary
        case .starting: return .orange
        case .mirroring: return .blue
        case .stopping: return .orange
        case .failed: return .red
        }
    }
}

private struct StatusCard: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        GroupBox("投屏状态") {
            HStack(spacing: 12) {
                Image(systemName: store.sessionState.symbolName)
                    .font(.title2)
                    .foregroundStyle(store.sessionState.isFailure ? .red : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.sessionSummary)
                        .font(.headline)
                    if let message = store.globalErrorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Text("单台停止、关闭窗口或连接失败不会停止其他手机。退出镜连会停止本应用启动的全部投屏。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isMirroring {
                    Button("停止全部", role: .destructive) { store.stopMirroring() }
                }
            }
            .padding(4)
        }
    }
}

private struct EmptySelectionCard: View {
    @ObservedObject var store: MirrorSessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("勾选要投屏的 Android 设备")
                .font(.headline)
            Text("左侧可以同时勾选多台已授权手机；点击“开始投屏”后会分别打开窗口。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { openWindow(id: "wireless") } label: {
                Label("无线连接手机", systemImage: "wifi")
            }
            if !store.readyDevices.isEmpty {
                Button("全选已连接设备") { store.selectAllReadyDevices() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct ToolchainMissingCard: View {
    var body: some View {
        GroupBox("需要修复安装") {
            Label("应用没有找到内置的 ADB / scrcpy。请重新下载完整的镜连安装包，不要只复制可执行文件。", systemImage: "shippingbox")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(4)
        }
    }
}

private struct LogCard: View {
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { store.logsExpanded },
            set: { store.logsExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("用于定位 USB、Wi-Fi、ADB 或 scrcpy 启动问题；日志会标注对应手机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") { store.clearLogs() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                ScrollView {
                    Text(store.logLines.isEmpty ? "暂无日志" : store.logLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 90, maxHeight: 180)
            }
            .padding(.top, 8)
        } label: {
            Label("诊断日志", systemImage: "list.bullet.rectangle")
        }
    }
}
