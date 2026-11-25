import SwiftUI

private typealias SidebarViewState<Value> = SwiftUI.State<Value>

struct SidebarView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @Environment(\.openWindow) private var openWindow
    @SidebarViewState private var settingsDevice: AndroidDevice?
    @SidebarViewState private var settingsKnownDevice: KnownDevice?

    private var offlineFavorites: [KnownDevice] {
        let connectedIdentities = Set(store.devices.compactMap { device in
            DevicePreferences.identity(for: device) ?? (device.hardwareSerial ?? (device.isWireless ? nil : device.serial)).map { "hardware:\($0)" }
        })
        return store.knownDevices.filter { $0.preferences.favorite && !connectedIdentities.contains($0.id) }
    }

    var body: some View {
        let _ = language.selection
        List {
            Section {
                if store.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(store.isRefreshing ? L10n.tr("正在扫描设备…") : L10n.tr("还没有发现设备"), systemImage: "iphone.slash")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                } else {
                    ForEach(store.devices) { device in
                        DeviceRow(
                            device: device,
                            displayName: store.displayName(for: device),
                            displaySerial: store.displaySerial(for: device),
                            favorite: store.preferences(for: device).favorite,
                            sessionState: store.sessionState(for: device),
                            isSelected: store.selectedDeviceIDs.contains(device.id),
                            onSelectionChanged: { isSelected in
                                store.setDeviceSelected(device.id, isSelected: isSelected)
                            }
                        )
                        .contextMenu {
                            Button(L10n.tr("设备设置…")) { settingsDevice = device }
                        }
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

            if !offlineFavorites.isEmpty {
                Section(L10n.tr("离线常用设备")) {
                    ForEach(offlineFavorites) { device in
                        Button { settingsKnownDevice = device } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "star").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.displayName).foregroundStyle(.primary).lineLimit(2)
                                    Text(L10n.tr("未连接 · 点按管理设置"))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
            }

        }
        .listStyle(.sidebar)
        .sheet(item: $settingsDevice) { device in DevicePreferencesSheet(store: store, device: device) }
        .sheet(item: $settingsKnownDevice) { device in DevicePreferencesSheet(store: store, knownDevice: device) }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.toolchainAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.sessionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.selectedDevices.isEmpty {
                    Text(L10n.tr("已选 %@ 台", String(store.selectedDevices.count)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject private var language = LanguageStore.shared
    let device: AndroidDevice
    let displayName: String
    let displaySerial: String?
    let favorite: Bool
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
                    HStack(spacing: 4) {
                        Text(displayName).lineLimit(2)
                        if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }
                    }
                    if displayName != device.displayName, device.displayName != device.serial {
                        Text(device.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text([device.transport, device.state.title].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            .help("\(displayName)\n\(device.transport) · \(device.state.title)")
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
