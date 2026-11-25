import AppKit
import SwiftUI
import Combine

private typealias ContentViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var store: MirrorSessionStore
    @ObservedObject var updates: AppUpdateStore
    @ObservedObject var wireless: WirelessConnectionStore
    @ContentViewState private var windowHandle = ControlWindowHandle()

    var body: some View {
        let _ = language.selection
        VStack(spacing: 0) {
            DetailView(store: store, wireless: wireless)
            HStack(spacing: 16) {
                if #available(macOS 14.0, *) {
                    SettingsLink { Text(L10n.tr("设置")) }
                } else {
                    Button(L10n.tr("设置")) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
                Button(updates.installationPending ? L10n.tr("安装更新") : L10n.tr("检查更新")) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            .font(.caption).buttonStyle(.link)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 500, minHeight: 360)
        .background(SceneWindowReference { window in
            windowHandle.window = window
            // SwiftUI restores saved geometry instead of defaultSize. Migrate
            // only this scene once; subsequent user resizing stays untouched.
            DispatchQueue.main.async { [weak window] in
                let key = "mainWindowSimpleLayoutV3"
                guard let window, !UserDefaults.standard.bool(forKey: key) else { return }
                window.setContentSize(NSSize(width: 540, height: 400))
                store.logsExpanded = false
                UserDefaults.standard.set(true, forKey: key)
            }
            // Capture only this SwiftUI scene, never the key window: a mirror
            // or Settings may become key while video startup is in flight.
            store.onMirrorWindowReady = { [weak window, weak connections = wireless] in
                connections?.close()
                window?.close()
            }
        })
        .onAppear { store.refresh(); wireless.open() }
        .onDisappear { wireless.close() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === windowHandle.window else { return }
            wireless.close()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === windowHandle.window else { return }
            wireless.open()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            store.refresh(silent: true)
        }
    }
}

private final class ControlWindowHandle {
    weak var window: NSWindow?
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
