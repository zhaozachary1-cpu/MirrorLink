import SwiftUI

private typealias DetailViewState<Value> = SwiftUI.State<Value>

struct DetailView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var wireless: WirelessConnectionStore

    var body: some View {
        let _ = language.selection
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if wireless.mode == .nearby {
                    Text(L10n.tr("连接手机，开始投屏"))
                        .font(.title2.weight(.semibold))
                        .padding(.top, 4)
                }

                if store.globalErrorMessage != nil { StatusCard(store: store) }

                if !store.displayedDevices.isEmpty {
                    DeviceSessionsCard(store: store)
                }

                WirelessConnectionView(store: wireless, sessions: store)
                    .id("wireless")

                if !store.toolchainAvailable {
                    ToolchainMissingCard()
                }

            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: wireless.mode) { mode in
            if mode != .nearby { proxy.scrollTo("wireless", anchor: .top) }
        }
        }
    }
}

private struct DeviceSessionsCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.displayedDevices) { device in
                    DeviceSessionRow(device: device, store: store)
                        .padding(18)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
                }
            }
        }
    }
}

private struct DeviceSessionRow: View {
    @ObservedObject private var language = LanguageStore.shared
    let device: AndroidDevice
    @ObservedObject var store: MirrorSessionStore

    private var state: MirrorSessionState {
        store.sessionState(for: device)
    }

    private var connection: AndroidDevice? { store.connectedDevice(for: device.id) }

    private var guidance: String? {
        if device.isWireless {
            guard let connection else { return L10n.tr("连接已断开，请重新连接手机。") }
            return connection.state == .ready ? nil : L10n.tr("请解锁手机后重新连接。")
        }
        guard let connection else {
            return L10n.tr("连接已断开，请重新插好数据线。")
        }
        switch connection.state {
        case .ready: return nil
        case .unauthorized: return L10n.tr("请解锁手机，允许 USB 调试。")
        case .offline, .unknown: return L10n.tr("请解锁手机，重新插好数据线。")
        }
    }

    private var statusTitle: String {
        if state == .idle { return connection?.state.title ?? L10n.tr("已断开") }
        return state.title
    }

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "iphone")
                    .font(.title.weight(.light)).foregroundStyle(.blue)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(store.displayName(for: device))
                            .font(.headline)
                            .lineLimit(2)
                    }
                    if store.displayName(for: device) != device.displayName, device.displayName != device.serial {
                        Text(device.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(statusTitle).font(.callout).foregroundStyle(stateTint)
                }
                Spacer()
                if state == .starting || state == .stopping { ProgressView().controlSize(.small) }
                Button {
                    if store.isMirroring(for: device.id) { store.stopMirroring(for: device.id) }
                    else { store.startMirroring(for: device.id) }
                } label: {
                    Text(store.isMirroring(for: device.id)
                        ? (state == .starting ? L10n.tr("取消") : L10n.tr("停止投屏"))
                        : (state.isFailure ? L10n.tr("重新投屏") : L10n.tr("开始投屏")))
                        .font(.body.weight(.semibold)).frame(minWidth: 104, minHeight: 28)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(store.isMirroring(for: device.id) ? .secondary : .blue)
                .disabled(state == .stopping || (!store.isMirroring(for: device.id) && !store.canStart(for: device.id)))
                .accessibilityLabel(L10n.tr("%@：%@", store.displayName(for: device),
                    store.isMirroring(for: device.id) ? L10n.tr("停止投屏") : L10n.tr("开始投屏")))
            }
            if store.reconnectStatus(for: device.id) != nil {
                HStack(alignment: .top) {
                    Label(L10n.tr("正在重新连接…"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L10n.tr("取消恢复")) { store.cancelReconnect(for: device.id) }
                        .buttonStyle(.bordered).fixedSize()
                }
            }
            if state.isFailure, guidance == nil {
                Text(L10n.tr("投屏中断，请重试。"))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let guidance {
                Text(guidance)
                    .font(.callout)
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

struct OfflineFavoritesCard: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @DetailViewState private var editingID: String?

    private var favorites: [KnownDevice] {
        let connected = Set(store.devices.compactMap { device in
            DevicePreferences.identity(for: device) ?? (device.hardwareSerial ?? (device.isWireless ? nil : device.serial)).map { "hardware:\($0)" }
        })
        return store.knownDevices.filter { $0.preferences.favorite && !connected.contains($0.id) }
    }

    var body: some View {
        let _ = language.selection
        if !favorites.isEmpty {
            DisclosureGroup(L10n.tr("离线常用设备")) {
                ForEach(favorites) { device in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editingID = editingID == device.id ? nil : device.id } label: {
                            Label(device.displayName, systemImage: "star")
                        }.buttonStyle(.borderless)
                        if editingID == device.id {
                            DevicePreferencesEditor(store: store, knownDevice: device) { editingID = nil }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}

private struct ToolchainMissingCard: View {
    @ObservedObject private var language = LanguageStore.shared
    var body: some View {
        let _ = language.selection
        GroupBox(L10n.tr("需要修复安装")) {
            Label(L10n.tr("应用文件不完整，请重新安装镜连。"), systemImage: "shippingbox")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(4)
        }
    }
}

struct LogCard: View {
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
                    Text(L10n.tr("连接与投屏的详细记录。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L10n.tr("清空")) { store.clearLogs() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                ScrollView {
                    Text(hasPresentationMode ? L10n.tr("演示模式已隐藏日志，可导出脱敏反馈。") : (store.logLines.isEmpty ? L10n.tr("暂无日志") : store.logLines.joined(separator: "\n")))
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
