import SwiftUI

// Keep the macOS 13-compatible property wrapper; some CLT SDKs also expose a
// newer State macro whose SwiftUIMacros plugin is available only in full Xcode.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct UpdateSettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updates: AppUpdateStore
    @ViewState private var draftFeed = ""

    var body: some View {
        let _ = language.selection
        Section(L10n.tr("应用更新")) {
            LabeledContent(L10n.tr("当前版本"), value: L10n.tr("%@（%@）", updates.version, updates.build))
            if updates.isConfigured {
                DisclosureGroup(L10n.tr("更新来源")) {
                    Text(updates.feedAddress)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Button(updates.installationPending ? L10n.tr("安装已下载的更新…") : L10n.tr("检查更新…")) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
                if let date = updates.lastCheckDate {
                    Text(L10n.tr("上次检查：%@", L10n.formattedDate(date)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(L10n.tr("自动检查更新"), isOn: Binding(
                get: { updates.automaticallyChecks },
                set: { updates.setAutomaticallyChecks($0) }
            ))
            .disabled(!updates.isConfigured)
            Text(updates.status)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if updates.canConfigureFeed {
                DisclosureGroup(L10n.tr("设置更新地址")) {
                    TextField(L10n.tr("发布者提供的 HTTPS appcast.xml 地址"), text: $draftFeed)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.tr("保存更新地址")) { updates.saveFeed(draftFeed) }
                    Text(L10n.tr("仅安装签名验证通过的更新。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onAppear { draftFeed = updates.feedAddress }
            }
        }
    }
}
