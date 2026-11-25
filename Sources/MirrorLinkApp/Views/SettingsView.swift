import SwiftUI

private typealias SettingsViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var updates: AppUpdateStore
    private var paths: ToolPaths? { store.paths }
    private var distributionNote: String {
        let channel = Bundle.main.object(forInfoDictionaryKey: "MirrorLinkDistributionChannel") as? String
        if channel == "developer-id" {
            return L10n.tr("Developer ID 已签名；公证结果见安装包说明。")
        }
        if channel == "community" {
            return L10n.tr("社区版未经 Apple 公证，首次打开可能需手动允许。仅从官方 GitHub 下载，勿关闭安全检查。")
        }
        return L10n.tr("本地体验版未经 Apple 公证，其他 Mac 可能无法打开。")
    }

    var body: some View {
        let _ = language.selection
        Form {
            Section("语言 / Language") {
                Picker(L10n.tr("显示语言"), selection: $language.selection) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.nativeDisplayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(L10n.tr("画质与稳定性")) {
                MirrorQualityControls(profile: $store.qualityProfile)
            }

            Section(L10n.tr("多窗口排列")) {
                Picker(L10n.tr("启动时排列"), selection: $store.windowLayout) {
                    ForEach(MirrorWindowLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
            }

            StorageSettingsSection()

            UpdateSettingsView(updates: updates)

            Section(L10n.tr("设备与诊断")) {
                ForEach(store.displayedDevices) { device in
                    DeviceSettingsRow(store: store, device: device)
                }
                OfflineFavoritesCard(store: store)
                LogCard(store: store)
            }
            Section {
              DisclosureGroup(L10n.tr("关于镜连")) {
                LabeledContent(L10n.tr("状态")) {
                    Label(paths?.isUsable == true ? L10n.tr("已就绪") : L10n.tr("缺少文件"), systemImage: paths?.isUsable == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(paths?.isUsable == true ? .green : .orange)
                }
                if let paths {
                    LabeledContent(L10n.tr("组件目录")) {
                        Text(paths.root.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                Text(distributionNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
              }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 590)
        .scenePadding()
    }
}

private struct DeviceSettingsRow: View {
    @ObservedObject var store: MirrorSessionStore
    let device: AndroidDevice
    @SettingsViewState private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                DevicePreferencesEditor(store: store, device: device) { expanded = false }
                if let video = store.videoStatus(for: device.id) {
                    Text(video.configurationSummary).font(.caption).foregroundStyle(.secondary)
                    if let resolution = video.resolution {
                        Text(L10n.tr("接收画面：%@ px", resolution.displayText)).font(.caption)
                    }
                    if let warning = video.warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                }
                if case let .failed(message) = store.sessionState(for: device) {
                    Text(store.isPresentationMode(for: device) ? L10n.tr("投屏中断，请重试。") : message)
                        .font(.caption).foregroundStyle(.red)
                }
                if store.isMirroring(for: device.id) {
                    Button(L10n.tr("重新投屏")) { store.restartMirroring(for: device.id) }
                        .disabled(store.sessionState(for: device) == .stopping)
                }
                DeviceToolsView(store: store, device: device)
            }.padding(.vertical, 8)
        } label: {
            Text(store.displayName(for: device))
        }
    }
}
