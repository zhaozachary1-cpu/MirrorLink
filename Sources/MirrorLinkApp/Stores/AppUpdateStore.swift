import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdateStore: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var isConfigured = false
    @Published private var statusMessage = L10n.message("更新服务尚未配置。")
    var status: String { statusMessage.resolved }
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
            showNotice(L10n.tr("暂时无法检查更新"), message: L10n.tr("%@ 请在设置中填写更新地址。", status))
            return
        }
        statusMessage = L10n.message("正在检查更新…")
        controller.checkForUpdates(nil)
    }

    @discardableResult
    func saveFeed(_ address: String) -> Bool {
        guard canConfigureFeed, !controller.updater.sessionInProgress else {
            showNotice(L10n.tr("暂时不能修改"), message: L10n.tr("更新过程中不能更换更新地址，请先完成或取消本次更新。"))
            return false
        }
        guard let url = UpdateConfiguration.validatedFeedURL(address) else {
            showNotice(L10n.tr("更新地址无效"), message: L10n.tr("请输入有效的 HTTPS 更新地址，不含账号密码。"))
            return false
        }
        feedAddress = url.absoluteString
        defaults.set(feedAddress, forKey: UpdateConfiguration.customFeedKey)
        if started {
            controller.updater.resetUpdateCycle()
            statusMessage = L10n.message("更新地址已保存，可以检查更新。")
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
            statusMessage = L10n.message("此构建缺少有效的更新验证公钥，已禁止在线更新。")
            return
        }
        guard UpdateConfiguration.validatedFeedURL(feedAddress) != nil else {
            statusMessage = L10n.message("尚未配置更新地址。")
            return
        }
        do {
            try controller.updater.start()
            started = true
            isConfigured = true
            statusMessage = L10n.message("可检查更新。下载后由你确认安装并重新启动。")
            lastCheckDate = controller.updater.lastUpdateCheckDate
        } catch {
            statusMessage = L10n.message("更新器启动失败：%@", error.localizedDescription)
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feedAddress }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard UpdateConfiguration.validatedFeedURL(feedAddress) != nil else {
            throw NSError(domain: "com.mirrorlink.update", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.tr("更新地址无效，已取消联网检查。")])
        }
        statusMessage = L10n.message("正在检查更新…")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        statusMessage = L10n.message("发现新版本 %@，请在更新窗口确认下载。", item.displayVersionString)
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // This may also mean the newer release does not support this OS.
        statusMessage = L10n.message("没有适用于此 Mac 的新版本。")
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        terminationApproved = false
        let error = error as NSError
        guard error.domain != SUSparkleErrorDomain || error.code != SUError.noUpdateError.rawValue else { return }
        statusMessage = L10n.message("更新未完成：%@ 原有应用保持可用。", error.localizedDescription)
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard activeSessionCount() > 0 else { return false }
        resumeInstallation = installHandler
        installationPending = true
        canCheckForUpdates = true
        statusMessage = L10n.message("更新已就绪，点击“安装更新”继续。")
        // Leave Sparkle's delegate stack before presenting application UI.
        DispatchQueue.main.async { [weak self] in self?.confirmPendingInstallation() }
        return true
    }

    private func confirmPendingInstallation() {
        guard let handler = resumeInstallation else { return }
        let count = activeSessionCount()
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = L10n.tr("停止投屏并安装更新？")
            alert.informativeText = L10n.tr("将停止 %@ 台投屏并安装更新，数据和设置保留。", String(count))
            alert.addButton(withTitle: L10n.tr("稍后安装"))
            alert.addButton(withTitle: L10n.tr("停止投屏并安装"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            stopSessions()
        }
        resumeInstallation = nil
        installationPending = false
        terminationApproved = true
        statusMessage = L10n.message("正在安装更新，即将重新启动…")
        handler()
    }

    // Sparkle may resume a previously staged update without the postponement
    // callback. Protect that termination path (and normal Quit) as well.
    func shouldAllowTermination() -> Bool {
        guard !terminationApproved, activeSessionCount() > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.tr("停止投屏并退出镜连？")
        alert.informativeText = L10n.tr("将关闭 %@ 台投屏，手机数据保留。", String(activeSessionCount()))
        alert.addButton(withTitle: L10n.tr("继续投屏"))
        alert.addButton(withTitle: L10n.tr("停止投屏并退出"))
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        stopSessions()
        return true
    }

    private func showNotice(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("好"))
        alert.runModal()
    }
}
