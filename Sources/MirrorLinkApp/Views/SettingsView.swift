import SwiftUI

struct SettingsView: View {
    let paths: ToolPaths?
    @ObservedObject var updates: AppUpdateStore
    private var distributionNote: String {
        let channel = Bundle.main.object(forInfoDictionaryKey: "MirrorLinkDistributionChannel") as? String
        if channel == "developer-id" {
            return "Developer ID 签名构建。公证结果以随安装包提供的发行清单及 macOS 安全验证为准。"
        }
        return "开发体验版：仅使用本地 ad-hoc 签名，未通过 Developer ID 签名与 Apple 公证。下载到其他 Mac 可能被系统拦截，不属于正式公开发行版。"
    }

    var body: some View {
        Form {
            UpdateSettingsView(updates: updates)
            Section("投屏组件") {
                LabeledContent("状态") {
                    Label(paths?.isUsable == true ? "已就绪" : "缺少文件", systemImage: paths?.isUsable == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(paths?.isUsable == true ? .green : .orange)
                }
                if let paths {
                    LabeledContent("组件目录") {
                        Text(paths.root.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            }

            Section("当前版本范围") {
                Text("支持 macOS 13 或更高版本，可同时投屏多台通过 USB 连接并授权的 Android 手机。每台手机独立显示，可分别开始、重试和停止；退出镜连会停止本应用启动的全部投屏。实际并行能力取决于 Mac 性能与 USB 连接。")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }

            Section("发布说明") {
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
