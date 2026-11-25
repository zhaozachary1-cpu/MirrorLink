import SwiftUI

private typealias DetailViewState<Value> = SwiftUI.State<Value>

struct DetailView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        let _ = language.selection
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.selectedDevices.isEmpty {
                    EmptySelectionCard(store: store)
                } else {
                    SelectedDevicesCard(store: store)
                }

                if store.globalErrorMessage != nil { StatusCard(store: store) }

                if !store.displayedDevices.isEmpty {
                    DeviceSessionsCard(store: store)
                }

                if !store.toolchainAvailable {
                    ToolchainMissingCard()
                }

                LogCard(store: store)
            }
            .padding(14)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .background(.regularMaterial)
    }
}

private struct SelectedDevicesCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        let _ = language.selection
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("已选择 %@ 台设备", String(store.selectedDevices.count)))
                            .font(.headline)
                    }
                    Spacer()
                    Button(L10n.tr("清除选择")) { store.clearDeviceSelection() }
                        .buttonStyle(.borderless)
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    Button {
                        store.startMirroring()
                    } label: {
                        Label(L10n.tr("开始所选投屏"), systemImage: "play.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStart)

                    Button(role: .destructive) {
                        store.stopMirroring()
                    } label: {
                        Label(L10n.tr("停止全部"), systemImage: "stop.fill")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.isMirroring && !store.hasPendingReconnect)
                }
            }
            .padding(2)
        }
    }
}

private struct DeviceSessionsCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        let _ = language.selection
        GroupBox(L10n.tr("设备与投屏")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.displayedDevices) { device in
                    DeviceSessionRow(device: device, store: store)
                    if device.id != store.displayedDevices.last?.id { Divider() }
                }
            }
            .padding(2)
        }
    }
}

private struct DeviceSessionRow: View {
    @ObservedObject private var language = LanguageStore.shared
    let device: AndroidDevice
    @ObservedObject var store: MirrorSessionStore
    @DetailViewState private var showsPreferences = false

    private var state: MirrorSessionState {
        store.sessionState(for: device)
    }

    private var connection: AndroidDevice? { store.connectedDevice(for: device.id) }

    private var videoStatus: MirrorVideoStatus? {
        state.isActive ? store.videoStatus(for: device.id) : nil
    }

    private var guidance: String? {
        if device.isWireless {
            guard let connection else { return L10n.tr("无线连接已断开。请确认同一 Wi-Fi 和无线调试，点击“无线连接”填写手机当前的连接端口。") }
            return connection.state == .ready ? nil : L10n.tr("无线设备尚未就绪。请检查无线调试授权与当前连接端口，必要时重新配对。")
        }
        guard let connection else {
            return L10n.tr("设备已断开。请检查 USB 连接，重新连接后可再次开始投屏。")
        }
        switch connection.state {
        case .ready: return nil
        case .unauthorized: return L10n.tr("请解锁这台手机，在“允许 USB 调试”提示中允许此电脑。")
        case .offline: return L10n.tr("设备处于离线状态。请解锁手机并重新插拔数据线，然后刷新设备。")
        case .unknown: return L10n.tr("无法确认设备状态。请检查数据线、USB 调试与手机授权后刷新。")
        }
    }

    private var statusTitle: String {
        if state == .idle { return connection?.state.title ?? L10n.tr("已断开") }
        return state.title
    }

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: state.symbolName)
                    .foregroundStyle(stateTint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(store.displayName(for: device))
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        if store.preferences(for: device).favorite {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange)
                                .accessibilityLabel(L10n.tr("常用设备"))
                        }
                    }
                    if store.displayName(for: device) != device.displayName, device.displayName != device.serial {
                        Text(device.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(device.transport)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(stateTint)
                    .fixedSize()
                Button { showsPreferences = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("设备设置"))
                .accessibilityLabel(L10n.tr("设备设置"))
            }
            if let reconnect = store.reconnectStatus(for: device.id) {
                HStack(alignment: .top) {
                    Label(reconnect, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L10n.tr("取消恢复")) { store.cancelReconnect(for: device.id) }
                        .buttonStyle(.bordered).fixedSize()
                }
            }
            if let videoStatus {
                DisclosureGroup(L10n.tr("画面信息")) {
                    Text(videoStatus.configurationSummary).font(.caption).foregroundStyle(.secondary)
                    Text(videoStatus.resolution.map { L10n.tr("接收画面：%@ px", $0.displayText) } ?? L10n.tr("等待画面尺寸"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                    if let warning = videoStatus.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            }
            HStack(spacing: 8) {
                Spacer()
                if store.isMirroring(for: device.id) {
                    Button {
                        store.restartMirroring(for: device.id)
                    } label: {
                        Label(L10n.tr("重新投屏"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state == .stopping)
                    .help(L10n.tr("只重启 %@ 的投屏，并应用当前选择的%@", store.displayName(for: device), (store.preferences(for: device).qualityProfile ?? store.qualityProfile).title))
                    Button(store.isRestartPending(for: device.id) ? L10n.tr("取消重启") : L10n.tr("停止")) {
                        store.stopMirroring(for: device.id)
                    }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(state == .stopping && !store.isRestartPending(for: device.id))
                        .help(L10n.tr("只停止 %@ 的投屏", store.displayName(for: device)))
                } else {
                    Button(state.isFailure ? L10n.tr("重试") : L10n.tr("开始")) { store.startMirroring(for: device.id) }
                        .buttonStyle(.bordered)
                        .disabled(!store.canStart(for: device.id))
                }
            }
            if case let .failed(message) = state {
                Text(store.isPresentationMode(for: device) ? L10n.tr("这台设备的投屏发生错误。可关闭演示模式查看详细诊断，或导出脱敏反馈。") : message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            DeviceToolsView(store: store, device: device)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showsPreferences) { DevicePreferencesSheet(store: store, device: device) }
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
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        let _ = language.selection
        GroupBox(L10n.tr("投屏状态")) {
            HStack(spacing: 12) {
                Image(systemName: store.sessionState.symbolName)
                    .font(.title2)
                    .foregroundStyle(store.sessionState.isFailure ? .red : .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.sessionSummary)
                        .font(.headline)
                    if let message = store.globalErrorMessage {
                        Text(store.displayedDevices.contains(where: { store.isPresentationMode(for: $0) }) ? L10n.tr("检测到连接或投屏问题，可使用设备工具导出脱敏反馈。") : message)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if store.isMirroring || store.hasPendingReconnect {
                    Button(L10n.tr("停止全部"), role: .destructive) { store.stopMirroring() }
                        .fixedSize()
                }
            }
            .padding(4)
        }
    }
}

private struct EmptySelectionCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = language.selection
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(L10n.tr("勾选要投屏的 Android 设备"))
                .font(.headline)
            Text(L10n.tr("连接 USB，或添加无线手机。"))
                .foregroundStyle(.secondary)
            Button { openWindow(id: "wireless") } label: {
                Label(L10n.tr("无线连接手机"), systemImage: "wifi")
            }
            if !store.readyDevices.isEmpty {
                Button(L10n.tr("全选已连接设备")) { store.selectAllReadyDevices() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

private struct ToolchainMissingCard: View {
    @ObservedObject private var language = LanguageStore.shared
    var body: some View {
        let _ = language.selection
        GroupBox(L10n.tr("需要修复安装")) {
            Label(L10n.tr("应用没有找到内置的 ADB / scrcpy。请重新下载完整的镜连安装包，不要只复制可执行文件。"), systemImage: "shippingbox")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(4)
        }
    }
}

private struct LogCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    private var hasPresentationMode: Bool {
        store.displayedDevices.contains { store.isPresentationMode(for: $0) }
            || store.knownDevices.contains { $0.preferences.presentationMode }
    }

    var body: some View {
        let _ = language.selection
        DisclosureGroup(isExpanded: Binding(
            get: { store.logsExpanded },
            set: { store.logsExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.tr("用于定位 USB、Wi-Fi、ADB 或 scrcpy 启动问题；日志会标注对应手机。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L10n.tr("清空")) { store.clearLogs() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                ScrollView {
                    Text(hasPresentationMode ? L10n.tr("演示模式下已隐藏诊断日志，避免显示设备标识。需要反馈时可使用设备工具中的脱敏导出。") : (store.logLines.isEmpty ? L10n.tr("暂无日志") : store.logLines.joined(separator: "\n")))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 90, maxHeight: 180)
            }
            .padding(.top, 8)
        } label: {
            Label(L10n.tr("诊断日志"), systemImage: "list.bullet.rectangle")
        }
    }
}
