import SwiftUI

// Keep the macOS 13-compatible property wrapper; some CLT SDKs also expose a
// newer State macro whose SwiftUIMacros plugin is available only in full Xcode.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct UpdateSettingsView: View {
    @ObservedObject var updates: AppUpdateStore
    @ViewState private var draftFeed = ""

    var body: some View {
        Section("应用更新") {
            LabeledContent("当前版本", value: "\(updates.version)（\(updates.build)）")
            HStack {
                Button(updates.installationPending ? "安装已下载的更新…" : "检查更新…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
                Spacer()
                if let date = updates.lastCheckDate {
                    Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("自动检查更新", isOn: Binding(
                get: { updates.automaticallyChecks },
                set: { updates.setAutomaticallyChecks($0) }
            ))
            .disabled(!updates.isConfigured)
            Text(updates.status)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if updates.canConfigureFeed {
                DisclosureGroup("设置更新地址") {
                    TextField("发布者提供的 HTTPS appcast.xml 地址", text: $draftFeed)
                        .textFieldStyle(.roundedBorder)
                    Button("保存更新地址") { updates.saveFeed(draftFeed) }
                    Text("只接受镜连内置公钥验证通过的更新包；不会将 GitHub 登录凭据写入应用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onAppear { draftFeed = updates.feedAddress }
            }
        }
    }
}
