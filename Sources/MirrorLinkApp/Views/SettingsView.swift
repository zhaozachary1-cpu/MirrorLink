import SwiftUI

struct SettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var updates: AppUpdateStore
    private var paths: ToolPaths? { store.paths }
    private var distributionNote: String {
        let channel = Bundle.main.object(forInfoDictionaryKey: "MirrorLinkDistributionChannel") as? String
        if channel == "developer-id" {
            return L10n.tr("Developer ID 签名构建。公证结果以随安装包提供的发行清单及 macOS 安全验证为准。")
        }
        if channel == "community" {
            return L10n.tr("免费社区版：更新包和更新清单使用镜连自己的签名校验，应用使用 ad-hoc 完整性签名，未获 Apple 公证。首次打开可能需要在“系统设置 → 隐私与安全”中手动允许；受管理的 Mac 可能不允许安装。请仅从镜连官方 GitHub 下载，不要关闭系统安全检查。")
        }
        return L10n.tr("开发体验版：仅使用本地 ad-hoc 签名，未通过 Developer ID 签名与 Apple 公证。下载到其他 Mac 可能被系统拦截，不属于正式公开发行版。")
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
                Text(L10n.tr("更改会立即应用于镜连界面，不会中断正在投屏的手机。系统菜单和更新弹窗可能需要下次启动应用后切换。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.tr("画质与稳定性")) {
                MirrorQualityControls(profile: $store.qualityProfile, showsAdditionalGuidance: true)
            }

            UpdateSettingsView(updates: updates)
            Section(L10n.tr("投屏组件")) {
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
            }

            Section(L10n.tr("当前版本范围")) {
                Text(L10n.tr("支持 macOS 13 或更高版本，可同时投屏多台通过 USB 授权或无线调试配对的 Android 手机。每台手机独立显示，可分别开始、重试、重新投屏和停止；退出镜连会停止本应用启动的全部投屏。实际并行能力取决于手机与 Mac 性能，以及 USB 或 Wi-Fi 连接。"))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("发布说明")) {
                Text(distributionNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 650)
        .scenePadding()
    }
}
