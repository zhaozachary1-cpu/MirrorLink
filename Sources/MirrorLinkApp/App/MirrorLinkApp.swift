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
    @StateObject private var language: LanguageStore
    @StateObject private var tools: DeviceToolsStore
    @Environment(\.openWindow) private var openWindow

    init() {
        _language = StateObject(wrappedValue: LanguageStore.shared)
        let sessions = MirrorSessionStore()
        _store = StateObject(wrappedValue: sessions)
        _tools = StateObject(wrappedValue: DeviceToolsStore(paths: sessions.paths))
        _wireless = StateObject(wrappedValue: WirelessConnectionStore(paths: sessions.paths) { [weak sessions] device in
            sessions?.connectAndMirror(device)
        })
        _updates = StateObject(wrappedValue: AppUpdateStore(
            activeSessionCount: { [weak sessions] in (sessions?.runningCount ?? 0) + (sessions?.hasPendingReconnect == true ? 1 : 0) },
            stopSessions: { [weak sessions] in sessions?.stopMirroring() }
        ))
    }

    var body: some Scene {
        let _ = language.selection
        // One control window owns all device sessions; reopening must not
        // create another timer/selection UI for the same store.
        Window(L10n.tr("镜连"), id: "main") {
            ContentView(store: store, updates: updates)
                .environmentObject(tools)
                .environment(\.locale, language.effectiveLocale)
                .onAppear {
                    appDelegate.store = store
                    appDelegate.updates = updates
                    appDelegate.wireless = wireless
                    appDelegate.tools = tools
                    appDelegate.openMainWindow = { openWindow(id: "main") }
                }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updates.installationPending ? L10n.tr("安装已下载的更新…") : L10n.tr("检查更新…")) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
            CommandMenu(L10n.tr("投屏")) {
                Button(L10n.tr("显示主窗口")) { openWindow(id: "main") }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button(L10n.tr("无线连接…")) { openWindow(id: "wireless") }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Button(L10n.tr("刷新设备")) { store.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button(L10n.tr("开始所选投屏")) { store.startMirroring() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!store.canStart)

                Button(L10n.tr("停止全部投屏")) { store.stopMirroring() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!store.isMirroring && !store.hasPendingReconnect)
            }
        }

        Window(L10n.tr("无线连接"), id: "wireless") {
            WirelessConnectionView(store: wireless)
                .environment(\.locale, language.effectiveLocale)
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            SettingsView(store: store, updates: updates)
                .environmentObject(tools)
                .environment(\.locale, language.effectiveLocale)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: MirrorSessionStore?
    weak var updates: AppUpdateStore?
    weak var wireless: WirelessConnectionStore?
    weak var tools: DeviceToolsStore?
    var openMainWindow: (() -> Void)?
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
        tools?.shutdown()
        wireless?.close()
        store?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A wireless/settings window may still be visible while the main
        // control window is closed. Always target the singleton main scene.
        guard let openMainWindow else { return true }
        openMainWindow()
        sender.activate(ignoringOtherApps: true)
        return false // SwiftUI's openWindow owns creation and restoration.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the control window must not silently stop active mirrors.
        // Dock click / cmd-0 restores it; Quit still shuts down owned children.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updates?.shouldAllowTermination() == false ? .terminateCancel : .terminateNow
    }
}
