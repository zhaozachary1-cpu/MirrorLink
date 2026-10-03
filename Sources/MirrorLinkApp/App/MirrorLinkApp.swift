import AppKit
import Darwin
import SwiftUI

@main
@MainActor
struct MirrorLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: MirrorSessionStore
    @StateObject private var updates: AppUpdateStore
    @StateObject private var wireless: WirelessConnectionStore
    @Environment(\.openWindow) private var openWindow

    init() {
        let sessions = MirrorSessionStore()
        _store = StateObject(wrappedValue: sessions)
        _wireless = StateObject(wrappedValue: WirelessConnectionStore(paths: sessions.paths) { [weak sessions] device in
            sessions?.connectAndMirror(device)
        })
        _updates = StateObject(wrappedValue: AppUpdateStore(
            activeSessionCount: { [weak sessions] in sessions?.runningCount ?? 0 },
            stopSessions: { [weak sessions] in sessions?.stopMirroring() }
        ))
    }

    var body: some Scene {
        WindowGroup("镜连", id: "main") {
            ContentView(store: store, updates: updates)
                .onAppear {
                    appDelegate.store = store
                    appDelegate.updates = updates
                    appDelegate.wireless = wireless
                }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updates.installationPending ? "安装已下载的更新…" : "检查更新…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            CommandMenu("投屏") {
                Button("无线连接…") { openWindow(id: "wireless") }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Button("刷新设备") { store.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("开始所选投屏") { store.startMirroring() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStart)

                Button("停止全部投屏") { store.stopMirroring() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!store.isMirroring)
            }
        }

        Window("无线连接", id: "wireless") {
            WirelessConnectionView(store: wireless)
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView(paths: store.paths, updates: updates)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: MirrorSessionStore?
    weak var updates: AppUpdateStore?
    weak var wireless: WirelessConnectionStore?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        wireless?.close()
        store?.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updates?.shouldAllowTermination() == false ? .terminateCancel : .terminateNow
    }
}
