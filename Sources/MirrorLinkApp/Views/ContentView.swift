import AppKit
import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var updates: AppUpdateStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = language.selection
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "wireless") } label: {
                    Label(L10n.tr("无线连接"), systemImage: "wifi")
                }
                .help(L10n.tr("配对或连接同一 Wi-Fi 下的 Android 手机"))
                .disabled(!store.toolchainAvailable)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.refresh()
                } label: {
                    Label(L10n.tr("刷新设备"), systemImage: "arrow.clockwise")
                }
                .help(L10n.tr("重新扫描已连接的 Android 设备"))
                .disabled(store.isRefreshing)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(SceneWindowReference { window in
            // SwiftUI restores saved geometry instead of defaultSize. Migrate
            // only this scene once; subsequent user resizing stays untouched.
            DispatchQueue.main.async { [weak window] in
                let key = "mainWindowCompactLayoutV1"
                guard let window, !UserDefaults.standard.bool(forKey: key) else { return }
                window.setContentSize(NSSize(width: 640, height: 420))
                UserDefaults.standard.set(true, forKey: key)
            }
            // Capture only this SwiftUI scene, never the key window: a mirror
            // or Settings may become key while video startup is in flight.
            store.onMirrorWindowReady = { [weak window] in window?.close() }
        })
        .onAppear { store.refresh() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.refresh(silent: true)
        }
    }
}

struct SceneWindowReference: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onResolve = onResolve
        return view
    }
    func updateNSView(_ view: WindowView, context: Context) { view.onResolve = onResolve }
    final class WindowView: NSView {
        var onResolve: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onResolve?(window) }
        }
    }
}
