import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var updates: AppUpdateStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "wireless") } label: {
                    Label("无线连接", systemImage: "wifi")
                }
                .help("配对或连接同一 Wi-Fi 下的 Android 手机")
                .disabled(!store.toolchainAvailable)
            }
            ToolbarItem(placement: .automatic) {
                Button { updates.checkForUpdates() } label: {
                    Label("检查更新", systemImage: "arrow.down.circle")
                }
                .help(updates.installationPending ? "安装已下载的更新" : "检查应用更新")
                .disabled(!updates.canCheckForUpdates)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.refresh()
                } label: {
                    Label("刷新设备", systemImage: "arrow.clockwise")
                }
                .help("重新扫描已连接的 Android 设备")
                .disabled(store.isRefreshing)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .onAppear { store.refresh() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.refresh(silent: true)
        }
    }
}
