import SwiftUI

struct SidebarView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = language.selection
        List {
            Section {
                if store.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(store.isRefreshing ? L10n.tr("正在扫描设备…") : L10n.tr("还没有发现设备"), systemImage: "iphone.slash")
                            .foregroundStyle(.secondary)
                        Text(L10n.tr("用 USB 数据线连接，或点击“无线连接”配对同一 Wi-Fi 下的 Android 手机。"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                } else {
                    ForEach(store.devices) { device in
                        DeviceRow(
                            device: device,
                            sessionState: store.sessionState(for: device),
                            isSelected: store.selectedDeviceIDs.contains(device.id),
                            onSelectionChanged: { isSelected in
                                store.setDeviceSelected(device.id, isSelected: isSelected)
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text(L10n.tr("设备"))
                    Spacer()
                    Text("\(store.devices.count)")
                        .foregroundStyle(.secondary)
                    if !store.readyDevices.isEmpty {
                        Button(L10n.tr("全选")) { store.selectAllReadyDevices() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }

            Section(L10n.tr("连接提示")) {
                Button { openWindow(id: "wireless") } label: {
                    Label(L10n.tr("无线连接手机…"), systemImage: "wifi")
                }
                .buttonStyle(.borderless)
                Label(L10n.tr("USB 连接需允许调试"), systemImage: "checkmark.shield")
                Label(L10n.tr("可同时勾选多台手机"), systemImage: "square.stack.3d.up")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.toolchainAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.toolchainAvailable ? L10n.tr("投屏组件就绪") : L10n.tr("缺少投屏组件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.selectedDevices.isEmpty {
                    Text(L10n.tr("已选 %@ 台", String(store.selectedDevices.count)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject private var language = LanguageStore.shared
    let device: AndroidDevice
    let sessionState: MirrorSessionState
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void

    var body: some View {
        let _ = language.selection
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: onSelectionChanged
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .lineLimit(1)
                    Text("\(device.transport) · \(device.state.title) · \(device.serial)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            .help("\(device.logLabel)\n\(device.detailText)")
            Spacer(minLength: 4)
            Image(systemName: sessionState.symbolName)
                .font(.caption)
                .foregroundStyle(sessionTint)
                .help(sessionState.title)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var sessionTint: Color {
        switch sessionState {
        case .idle: return .secondary
        case .starting: return .orange
        case .mirroring: return .blue
        case .stopping: return .orange
        case .failed: return .red
        }
    }
}
