import Combine
import Foundation

@MainActor
final class DeviceToolsStore: ObservableObject {
    typealias FeedbackExporter = @Sendable (String, [URL], URL, ProcessCancellation?) throws -> URL
    @Published private(set) var outputDirectory: URL
    @Published private var statuses: [String: LocalizedMessage] = [:]
    @Published private var errors: Set<String> = []
    @Published private var busy: Set<String> = []
    @Published private var screenshots: [String: URL] = [:]
    @Published private var healthReports: [String: DeviceHealthReport] = [:]
    @Published private var feedbackMessage: LocalizedMessage?
    @Published private(set) var feedbackIsBusy = false
    @Published private(set) var feedbackIsError = false
    @Published private(set) var lastFeedbackURL: URL?
    var feedbackStatus: String? { feedbackMessage?.resolved }
    private let service: DeviceToolsService?
    private let defaults: UserDefaults
    private let feedbackExporter: FeedbackExporter
    private let workers = DispatchGroup()
    private var tokens: [String: ProcessCancellation] = [:]
    private var operations: [String: UUID] = [:]
    private var statusVersions: [String: UUID] = [:]
    private var cancellationMessages: [String: LocalizedMessage] = [:]
    private var apkOperations: Set<String> = []
    private var operationStarts: [String: TimeInterval] = [:]
    private var operationEnds: [String: TimeInterval] = [:]
    private var feedbackToken: ProcessCancellation?
    private var hasShutdown = false
    static let directoryPreferenceKey = "deviceToolsOutputDirectory"

    init(paths: ToolPaths?, defaults: UserDefaults = .standard, outputDirectory: URL? = nil,
         service: DeviceToolsService? = nil,
         feedbackExporter: @escaping FeedbackExporter = { preview, attachments, destination, cancellation in
             try FeedbackExportService.export(preview: preview, attachments: attachments,
                 destination: destination, cancellation: cancellation)
         }) {
        self.service = service ?? paths.map { DeviceToolsService(paths: $0) }
        self.defaults = defaults
        self.feedbackExporter = feedbackExporter
        if let outputDirectory { self.outputDirectory = outputDirectory }
        else if let stored = defaults.string(forKey: Self.directoryPreferenceKey), stored.hasPrefix("/") {
            self.outputDirectory = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
            self.outputDirectory = pictures.appendingPathComponent("MirrorLink", isDirectory: true)
        }
    }

    func setOutputDirectory(_ directory: URL) throws {
        do {
            try ToolFileSafety.prepareDirectory(directory)
            let probe = directory.appendingPathComponent(".MirrorLink-write-check-" + UUID().uuidString)
            try ToolFileSafety.writeExclusive(Data(), to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch { throw DeviceToolsError.saveFailed }
        outputDirectory = directory.standardizedFileURL
        defaults.set(outputDirectory.path, forKey: Self.directoryPreferenceKey)
    }
    func isBusy(for id: String) -> Bool { busy.contains(id) }
    func status(for id: String) -> String? {
        guard let message = statuses[id] else { return nil }
        if apkOperations.contains(id), isBusy(for: id), let start = operationStarts[id] {
            let elapsed = Int(ProcessInfo.processInfo.systemUptime - start)
            if ["正在传输并安装 APK…", "正在手机上安装 APK…"].contains(message.key), tokens[id]?.isCancelled != true, elapsed >= 20 {
                return L10n.tr("正在安装 · %@ 秒，请查看手机授权", String(elapsed))
            }
            return L10n.tr("%@ · 已用 %@ 秒", message.resolved, String(elapsed))
        }
        return message.resolved
    }
    func isError(for id: String) -> Bool { errors.contains(id) }
    func lastScreenshotURL(for id: String) -> URL? { screenshots[id] }
    func healthReport(for id: String) -> DeviceHealthReport? { healthReports[id] }
    func windowState(for device: AndroidDevice) -> [String: Any] {
        let showAPK = apkOperations.contains(device.id) && (isBusy(for: device.id) ||
            operationEnds[device.id].map { ProcessInfo.processInfo.systemUptime - $0 < 8 } == true)
        return ["busy": isBusy(for: device.id), "status": status(for: device.id) ?? "",
         "installStatus": showAPK ? status(for: device.id) ?? "" : "",
         "isError": isError(for: device.id), "resultID": statusVersions[device.id]?.uuidString ?? "initial",
         "screenshotPath": screenshots[device.id]?.path ?? "", "directory": outputDirectory.path]
    }

    func captureScreenshot(for device: AndroidDevice) {
        let directory = outputDirectory
        perform(device, message: L10n.message("正在截取原始画面…")) { service, token, _ in
            .screenshot(try service.captureScreenshot(for: device, directory: directory, cancellation: token))
        }
    }
    func sendFile(_ url: URL, to device: AndroidDevice) {
        perform(device, message: L10n.message("正在发送文件…"),
                cancellationMessage: L10n.message("发送已停止，手机可能保留部分文件。")) { service, token, _ in
            .message(L10n.message("文件已发送到手机：%@", try service.sendFile(url, to: device, cancellation: token)))
        }
    }
    func installAPK(_ url: URL, to device: AndroidDevice, confirmed: Bool) {
        let start = ProcessInfo.processInfo.systemUptime
        perform(device, message: L10n.message("正在安装 APK…"),
                cancellationMessage: L10n.message("已停止等待，请在手机确认安装结果；已安装内容保留。"),
                isAPK: true) { service, token, progress in
            try service.installAPK(url, to: device, confirmed: confirmed, cancellation: token, progress: progress)
            return .message(L10n.message("APK 安装完成 · 用时 %@ 秒", String(Int(ProcessInfo.processInfo.systemUptime - start))))
        }
    }
    func home(for device: AndroidDevice) {
        perform(device, message: L10n.message("正在发送返回桌面指令…")) { service, token, _ in
            try service.home(for: device, cancellation: token)
            return .message(L10n.message("已发送返回桌面指令。"))
        }
    }
    func openAppDrawer(for device: AndroidDevice) {
        perform(device, message: L10n.message("正在请求应用抽屉…")) { service, token, _ in
            try service.openAppDrawer(for: device, cancellation: token)
            return .message(L10n.message("已发送应用抽屉指令；若桌面未响应，请尝试上滑兼容方式。"))
        }
    }
    func swipeUpForDrawer(for device: AndroidDevice) {
        perform(device, message: L10n.message("正在发送上滑手势…")) { service, token, _ in
            try service.swipeUpForDrawer(for: device, cancellation: token)
            return .message(L10n.message("已发送桌面上滑手势；不同桌面的显示方式可能不同。"))
        }
    }
    func runHealthCheck(for device: AndroidDevice) {
        perform(device, message: L10n.message("正在检测所选手机…")) { service, token, _ in
            .health(try service.healthCheck(for: device, cancellation: token))
        }
    }
    func cancel(for id: String) {
        guard let token = tokens[id] else { return }
        token.cancel()
        statuses[id] = L10n.message("正在取消…")
    }

    func exportFeedback(_ report: FeedbackReport, attachments: [URL], to destination: URL) {
        guard !hasShutdown, !feedbackIsBusy else { return }
        let preview = report.preview, token = ProcessCancellation()
        feedbackToken = token; feedbackIsBusy = true; feedbackIsError = false
        feedbackMessage = L10n.message("正在导出反馈包…")
        let exporter = feedbackExporter, workers = workers
        workers.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Leave on this worker, not in the main-queue publication below:
            // applicationWillTerminate waits synchronously on the main thread.
            defer { workers.leave() }
            let result = Result { try exporter(preview, attachments, destination, token) }
            DispatchQueue.main.async {
                guard let self, self.feedbackToken === token else { return }
                self.feedbackIsBusy = false; self.feedbackToken = nil
                switch result {
                case let .success(url):
                    self.lastFeedbackURL = url
                    self.feedbackMessage = L10n.message("反馈包已保存到本地，尚未发送。")
                case let .failure(error):
                    self.feedbackIsError = true
                    self.feedbackMessage = (error as? DeviceToolsError ?? .saveFailed).message
                }
            }
        }
    }
    func cancelFeedback() {
        feedbackToken?.cancel()
        if feedbackIsBusy { feedbackMessage = L10n.message("正在取消…") }
    }

    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true
        let activeTokens = Array(tokens.values) + [feedbackToken].compactMap { $0 }
        for token in activeTokens { token.cancel() }
        tokens.removeAll(); operations.removeAll(); cancellationMessages.removeAll(); busy.removeAll()
        feedbackToken = nil; feedbackIsBusy = false
        // Keep the app alive until the owned commands exit and their worker
        // defers close files/remove staging folders. No UI callback is needed.
        if workers.wait(timeout: .now() + 2) == .timedOut {
            for token in activeTokens { token.forceTerminateOwnedProcesses() }
            _ = workers.wait(timeout: .now() + 1)
        }
    }

    private enum Output: Sendable { case screenshot(URL), health(DeviceHealthReport), message(LocalizedMessage) }
    private func perform(_ device: AndroidDevice, message: LocalizedMessage,
                         cancellationMessage: LocalizedMessage = L10n.message("操作已取消。"),
                         isAPK: Bool = false,
                         operation: @escaping @Sendable (DeviceToolsService, ProcessCancellation,
                             @Sendable (LocalizedMessage) -> Void) throws -> Output) {
        let id = device.id
        guard !hasShutdown, !busy.contains(id) else { return }
        guard let service else { statuses[id] = DeviceToolsError.toolsMissing.message; errors.insert(id); return }
        let token = ProcessCancellation(), generation = UUID()
        statusVersions[id] = generation
        tokens[id] = token; operations[id] = generation; cancellationMessages[id] = cancellationMessage
        if isAPK { apkOperations.insert(id) } else { apkOperations.remove(id) }
        operationStarts[id] = ProcessInfo.processInfo.systemUptime; operationEnds[id] = nil
        busy.insert(id); errors.remove(id); statuses[id] = message
        let workers = workers
        workers.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { workers.leave() }
            let result = Result {
                try operation(service, token) { [weak self] message in
                    DispatchQueue.main.async {
                        guard let self, self.operations[id] == generation, !token.isCancelled else { return }
                        self.statuses[id] = message
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operations[id] == generation else { return }
                self.busy.remove(id); self.tokens[id] = nil; self.operations[id] = nil
                self.operationEnds[id] = ProcessInfo.processInfo.systemUptime
                let cancelledMessage = self.cancellationMessages.removeValue(forKey: id)
                if token.isCancelled {
                    self.statuses[id] = cancelledMessage ?? DeviceToolsError.cancelled.message
                    self.errors.insert(id)
                    return
                }
                switch result {
                case let .success(output):
                    switch output {
                    case let .screenshot(url): self.screenshots[id] = url; self.statuses[id] = L10n.message("原始 PNG 截图已保存。")
                    case let .health(report): self.healthReports[id] = report; self.statuses[id] = L10n.message("连接健康检测完成。")
                    case let .message(message): self.statuses[id] = message
                    }
                case let .failure(error):
                    self.errors.insert(id)
                    if let failure = error as? DeviceToolsError, case .cancelled = failure {
                        self.statuses[id] = cancelledMessage ?? failure.message
                    } else { self.statuses[id] = (error as? DeviceToolsError ?? .commandFailed).message }
                }
            }
        }
    }
}
