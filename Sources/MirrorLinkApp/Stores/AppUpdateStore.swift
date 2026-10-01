import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdateStore: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var isConfigured = false
    @Published private(set) var status = "更新服务尚未配置。"
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var installationPending = false
    @Published private(set) var feedAddress = ""

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    let bundledFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    var canConfigureFeed: Bool { bundledFeed?.isEmpty != false }

    private let defaults: UserDefaults
    private let activeSessionCount: () -> Int
    private let stopSessions: () -> Void
    private var controller: SPUStandardUpdaterController!
    private var subscriptions = Set<AnyCancellable>()
    private var started = false
    private var resumeInstallation: (() -> Void)?
    private var terminationApproved = false

    init(defaults: UserDefaults = .standard,
         activeSessionCount: @escaping () -> Int,
         stopSessions: @escaping () -> Void) {
        self.defaults = defaults
        self.activeSessionCount = activeSessionCount
        self.stopSessions = stopSessions
        super.init()
        feedAddress = UpdateConfiguration.effectiveFeed(
            bundled: bundledFeed,
            custom: defaults.string(forKey: UpdateConfiguration.customFeedKey)
        )?.absoluteString ?? ""
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        // Never install silently or send hardware profiling data.
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.sendsSystemProfile = false
        controller.updater.clearFeedURLFromUserDefaults()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] allowed in
                guard let self else { return }
                self.canCheckForUpdates = !self.started || allowed || self.installationPending
            }.store(in: &subscriptions)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecks = $0 }
            .store(in: &subscriptions)
        startIfConfigured()
    }

    func checkForUpdates() {
        if installationPending {
            confirmPendingInstallation()
            return
        }
        guard isConfigured, started else {
            showNotice("暂时无法检查更新", message: status + " 请在设置的“应用更新”中配置发布者提供的 HTTPS 更新地址。")
            return
        }
        status = "正在检查更新…"
        controller.checkForUpdates(nil)
    }

    @discardableResult
    func saveFeed(_ address: String) -> Bool {
        guard canConfigureFeed, !controller.updater.sessionInProgress else {
            showNotice("暂时不能修改", message: "更新过程中不能更换更新地址，请先完成或取消本次更新。")
            return false
        }
        guard let url = UpdateConfiguration.validatedFeedURL(address) else {
            showNotice("更新地址无效", message: "请使用完整的 HTTPS 地址，不能包含账号、密码或片段标记。")
            return false
        }
        feedAddress = url.absoluteString
        defaults.set(feedAddress, forKey: UpdateConfiguration.customFeedKey)
        if started {
            controller.updater.resetUpdateCycle()
            status = "更新地址已保存，可以检查更新。"
        } else {
            startIfConfigured()
        }
        return isConfigured
    }

    func setAutomaticallyChecks(_ value: Bool) {
        guard isConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = value
        automaticallyChecks = value
    }

    private func startIfConfigured() {
        guard UpdateConfiguration.hasValidPublicKey(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) else {
            status = "此构建缺少有效的更新验证公钥，已禁止在线更新。"
            return
        }
        guard UpdateConfiguration.validatedFeedURL(feedAddress) != nil else {
            status = "更新服务尚未发布；配置更新地址后即可使用，当前未进行联网检查。"
            return
        }
        do {
            try controller.updater.start()
            started = true
            isConfigured = true
            status = "可检查更新。下载后由你确认安装并重新启动。"
            lastCheckDate = controller.updater.lastUpdateCheckDate
        } catch {
            status = "更新器启动失败：\(error.localizedDescription)"
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feedAddress }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard UpdateConfiguration.validatedFeedURL(feedAddress) != nil else {
            throw NSError(domain: "com.mirrorlink.update", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "更新地址无效，已取消联网检查。"])
        }
        status = "正在检查更新…"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "发现新版本 \(item.displayVersionString)，请在更新窗口确认下载。"
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // This may also mean the newer release does not support this OS.
        status = "没有适用于此 Mac 的新版本。"
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        terminationApproved = false
        let error = error as NSError
        guard error.domain != SUSparkleErrorDomain || error.code != SUError.noUpdateError.rawValue else { return }
        status = "更新未完成：\(error.localizedDescription) 原有应用保持可用。"
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard activeSessionCount() > 0 else { return false }
        resumeInstallation = installHandler
        installationPending = true
        canCheckForUpdates = true
        status = "更新已就绪，正在等待结束投屏。点击“安装已下载的更新”继续。"
        // Leave Sparkle's delegate stack before presenting application UI.
        DispatchQueue.main.async { [weak self] in self?.confirmPendingInstallation() }
        return true
    }

    private func confirmPendingInstallation() {
        guard let handler = resumeInstallation else { return }
        let count = activeSessionCount()
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = "停止投屏并安装更新？"
            alert.informativeText = "目前有 \(count) 台手机正在启动或投屏。安装会停止镜连启动的投屏并重启应用，手机数据和应用设置不会被清除。"
            alert.addButton(withTitle: "稍后安装")
            alert.addButton(withTitle: "停止投屏并安装")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            stopSessions()
        }
        resumeInstallation = nil
        installationPending = false
        terminationApproved = true
        status = "正在安装更新，即将重新启动…"
        handler()
    }

    // Sparkle may resume a previously staged update without the postponement
    // callback. Protect that termination path (and normal Quit) as well.
    func shouldAllowTermination() -> Bool {
        guard !terminationApproved, activeSessionCount() > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "停止投屏并退出镜连？"
        alert.informativeText = "仍有 \(activeSessionCount()) 台手机正在启动或投屏。退出或安装更新会关闭镜连启动的投屏窗口，不会清除手机数据。"
        alert.addButton(withTitle: "继续投屏")
        alert.addButton(withTitle: "停止投屏并退出")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        stopSessions()
        return true
    }

    private func showNotice(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
