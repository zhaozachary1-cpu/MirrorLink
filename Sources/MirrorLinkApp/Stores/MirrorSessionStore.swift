import Combine
import Foundation
import Darwin

@MainActor
final class MirrorSessionStore: ObservableObject {
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var selectedDeviceIDs: Set<AndroidDevice.ID> = []
    @Published private(set) var sessionStates: [AndroidDevice.ID: MirrorSessionState] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var toolchainAvailable = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var globalErrorMessage: String?
    @Published var logsExpanded = false

    let paths: ToolPaths?

    @Published private var runningSessions: [AndroidDevice.ID: RunningMirrorSession] = [:]
    @Published private var sessionDevices: [AndroidDevice.ID: AndroidDevice] = [:]
    private let startupTimeout: TimeInterval
    private let snapshotProvider: (ToolPaths) -> ADBSnapshot
    private var shuttingDown = false
    private var hasResolvedInitialSelection = false

    init(
        paths: ToolPaths? = ToolPaths.discover(),
        startupTimeout: TimeInterval = 25,
        snapshotProvider: @escaping (ToolPaths) -> ADBSnapshot = { ADBService(paths: $0).snapshot() }
    ) {
        self.paths = paths
        self.startupTimeout = startupTimeout
        self.snapshotProvider = snapshotProvider
        self.toolchainAvailable = paths?.isUsable == true
        appendLog(paths == nil ? "未找到应用内置投屏组件。" : "已加载应用内置 ADB / scrcpy。")
    }

    var selectedDevices: [AndroidDevice] {
        devices.filter { selectedDeviceIDs.contains($0.id) }
    }

    var readyDevices: [AndroidDevice] {
        devices.filter { $0.state == .ready }
    }

    /// Keep individual controls visible after deselection or USB removal.
    var displayedDevices: [AndroidDevice] {
        var visible = sessionDevices
        for device in devices where selectedDeviceIDs.contains(device.id) || visible[device.id] != nil {
            visible[device.id] = device
        }
        return visible.values.sorted {
            $0.logLabel.localizedStandardCompare($1.logLabel) == .orderedAscending
        }
    }

    var runningCount: Int { runningSessions.count }

    var startableSelectedCount: Int {
        selectedDevices.filter { canStart(for: $0.id) }.count
    }

    var sessionSummary: String {
        let counts: [(MirrorSessionState, String)] = [
            (.mirroring, "台正在投屏"), (.starting, "台正在启动"), (.stopping, "台正在停止")
        ]
        var parts = counts.compactMap { state, label -> String? in
            let count = sessionStates.values.filter { $0 == state }.count
            return count == 0 ? nil : "\(count) \(label)"
        }
        let failures = sessionStates.values.filter(\.isFailure).count
        if failures > 0 { parts.append("\(failures) 台失败") }
        return parts.isEmpty ? "尚未开始投屏" : parts.joined(separator: " · ")
    }

    var isMirroring: Bool {
        !runningSessions.isEmpty
    }

    var canStart: Bool {
        toolchainAvailable
            && !shuttingDown
            && startableSelectedCount > 0
    }

    var sessionState: MirrorSessionState {
        let states = Array(sessionStates.values)
        if let globalErrorMessage { return .failed(globalErrorMessage) }
        if let message = states.compactMap({ state -> String? in
            guard case let .failed(message) = state else { return nil }
            return message
        }).first {
            return .failed(message)
        }
        if states.contains(.starting) { return .starting }
        if states.contains(.mirroring) { return .mirroring }
        if states.contains(.stopping) { return .stopping }
        return .idle
    }

    func sessionState(for device: AndroidDevice) -> MirrorSessionState {
        sessionStates[device.id] ?? .idle
    }

    func isMirroring(for deviceID: AndroidDevice.ID) -> Bool {
        runningSessions[deviceID] != nil
    }

    func connectedDevice(for deviceID: AndroidDevice.ID) -> AndroidDevice? {
        devices.first { $0.id == deviceID }
    }

    func canStart(for deviceID: AndroidDevice.ID) -> Bool {
        toolchainAvailable && !shuttingDown && !isMirroring(for: deviceID)
            && connectedDevice(for: deviceID)?.state == .ready
    }

    func setDeviceSelected(_ deviceID: AndroidDevice.ID, isSelected: Bool) {
        hasResolvedInitialSelection = true
        if isSelected {
            selectedDeviceIDs.insert(deviceID)
        } else {
            selectedDeviceIDs.remove(deviceID)
        }
    }

    func selectAllReadyDevices() {
        hasResolvedInitialSelection = true
        selectedDeviceIDs = Set(readyDevices.map(\.id))
    }

    func clearDeviceSelection() {
        hasResolvedInitialSelection = true
        selectedDeviceIDs.removeAll()
    }

    func refresh(silent: Bool = false) {
        guard !isRefreshing, !shuttingDown else { return }
        guard let paths, paths.isUsable else {
            toolchainAvailable = false
            if !silent { appendLog("刷新失败：应用内置工具不存在。") }
            return
        }

        isRefreshing = true
        if !silent { appendLog("正在扫描 USB 设备…") }
        let provider = snapshotProvider
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = provider(paths)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                guard !self.shuttingDown else { return }

                let changed = self.devices != snapshot.devices
                self.devices = snapshot.devices
                self.lastRefresh = Date()
                self.toolchainAvailable = paths.isUsable
                for diagnostic in snapshot.diagnostics { self.appendLog(diagnostic) }

                // Remember explicit choices for this app run, including across
                // reconnects. A refresh never undoes Clear Selection or starts a phone.
                if !self.hasResolvedInitialSelection && !snapshot.devices.isEmpty {
                    self.hasResolvedInitialSelection = true
                    let ready = snapshot.devices.filter { $0.state == .ready }
                    if ready.count == 1 {
                        self.selectedDeviceIDs = [ready[0].id]
                    } else if snapshot.devices.count == 1 {
                        self.selectedDeviceIDs = [snapshot.devices[0].id]
                    }
                }

                if changed || !silent {
                    self.appendLog(snapshot.devices.isEmpty ? "没有发现 USB 设备。" : "发现 \(snapshot.devices.count) 个 USB 设备。")
                }
            }
        }
    }

    /// Starts every selected, ready device that is not already running.
    /// Each device gets its own scrcpy process and independent failure state.
    func startMirroring() {
        guard !shuttingDown else { return }
        guard let paths, paths.isUsable else {
            failGlobally("无法启动：应用内置工具不存在。")
            return
        }

        let selected = selectedDevices
        guard !selected.isEmpty else {
            failGlobally("请先勾选至少一台设备。")
            return
        }

        globalErrorMessage = nil
        for device in selected where device.state != .ready {
            appendLog("跳过 \(device.logLabel)：设备当前不可用（\(device.state.title)）。")
        }

        let readyToStart = selected.filter { device in
            device.state == .ready && !isMirroring(for: device.id)
        }
        guard !readyToStart.isEmpty else {
            if selected.contains(where: { isMirroring(for: $0.id) }) {
                appendLog("所选设备已经在投屏中。")
            } else {
                failGlobally("所选设备中没有已连接且已授权的手机。")
            }
            return
        }

        for device in readyToStart {
            startSession(for: device, paths: paths)
        }
    }

    func startMirroring(for deviceID: AndroidDevice.ID) {
        guard !shuttingDown else { return }
        guard let paths, paths.isUsable else {
            failGlobally("无法启动：应用内置工具不存在。")
            return
        }
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            failGlobally("找不到要投屏的设备，请刷新设备列表。")
            return
        }
        guard device.state == .ready else {
            failGlobally(device.state == .unauthorized ? "请解锁手机并允许 USB 调试。" : "设备当前不可用：\(device.state.title)。")
            return
        }
        guard !isMirroring(for: device.id) else {
            appendLog("\(device.logLabel) 已经在投屏中。")
            return
        }

        globalErrorMessage = nil
        startSession(for: device, paths: paths)
    }

    func stopMirroring() {
        let activeIDs = Array(runningSessions.keys)
        guard !activeIDs.isEmpty else { return }
        appendLog("正在停止 \(activeIDs.count) 个投屏窗口…")
        for deviceID in activeIDs {
            stopMirroring(for: deviceID, appendingLog: false)
        }
    }

    func stopMirroring(for deviceID: AndroidDevice.ID) {
        stopMirroring(for: deviceID, appendingLog: true)
    }

    // Called synchronously on application termination, so no child outlives Quit.
    // Never kill an ADB daemon or another app's scrcpy session.
    func shutdown() {
        shuttingDown = true
        let sessions = Array(runningSessions.values)
        for session in sessions {
            session.stopRequested = true
            sessionStates[session.device.id] = .stopping
            if session.process.isRunning { session.process.terminate() }
        }

        let deadline = Date().addingTimeInterval(1.5)
        while sessions.contains(where: { $0.process.isRunning }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        for session in sessions where session.process.isRunning {
            kill(session.process.processIdentifier, SIGKILL)
        }
    }

    func clearLogs() {
        logLines.removeAll()
        globalErrorMessage = nil
    }

    private func startSession(for device: AndroidDevice, paths: ToolPaths) {
        let command = ScrcpyCommand(paths: paths)
        let token = UUID()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let readers = DispatchGroup()
        process.executableURL = paths.scrcpy
        process.arguments = command.arguments(for: device)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in command.environment(for: device) { environment[key] = value }
        process.environment = environment
        process.currentDirectoryURL = paths.root

        let session = RunningMirrorSession(
            device: device,
            token: token,
            process: process,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
        runningSessions[device.id] = session
        sessionDevices[device.id] = device
        sessionStates[device.id] = .starting
        appendLog("正在启动 \(device.logLabel) 的投屏窗口…")

        // Register before run(): even an immediately failing child must drain
        // both output streams before we publish its final state.
        readers.enter()
        readers.enter()

        process.terminationHandler = { [weak self] process in
            readers.notify(queue: .global(qos: .utility)) {
                DispatchQueue.main.async {
                    self?.handleTermination(process, deviceID: device.id, token: token)
                }
            }
        }

        do {
            try process.run()
            for (pipe, stream) in [(outputPipe, "stdout"), (errorPipe, "stderr")] {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    defer { readers.leave() }
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        guard !data.isEmpty else { break }
                        DispatchQueue.main.async {
                            self?.consume(data, stream: stream, deviceID: device.id, token: token)
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + startupTimeout) { [weak self] in
                guard let self,
                      let current = self.runningSessions[device.id],
                      current.token == token,
                      self.sessionStates[device.id] == .starting else { return }
                self.failDevice(device.id, message: "启动超时：尚未收到手机画面。请解锁手机、确认 USB 调试授权后重试。")
                self.terminateOwnedProcess(deviceID: device.id, token: token)
            }
        } catch {
            readers.leave()
            readers.leave()
            process.terminationHandler = nil
            runningSessions[device.id] = nil
            failDevice(device.id, message: "启动失败：\(error.localizedDescription)")
        }
    }

    private func stopMirroring(for deviceID: AndroidDevice.ID, appendingLog: Bool) {
        guard let session = runningSessions[deviceID] else { return }
        session.stopRequested = true
        sessionStates[deviceID] = .stopping
        if appendingLog { appendLog("正在停止 \(session.device.logLabel) 的投屏…") }
        terminateOwnedProcess(deviceID: deviceID, token: session.token)
    }

    private func terminateOwnedProcess(deviceID: AndroidDevice.ID, token: UUID) {
        guard let session = runningSessions[deviceID], session.token == token, session.process.isRunning else { return }
        let process = session.process
        process.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self,
                  let current = self.runningSessions[deviceID],
                  current.token == token,
                  process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func consume(_ data: Data, stream: String, deviceID: AndroidDevice.ID, token: UUID) {
        guard let session = runningSessions[deviceID], session.token == token else { return }
        var buffer = (session.pendingOutput[stream] ?? Data()) + data
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            appendLog("[\(session.device.logLabel)] \(line)")
            // scrcpy emits this after initializing its video texture, not merely
            // after Process.run(). That distinction prevents a false success UI.
            if sessionStates[deviceID] == .starting && line.contains("Texture:") {
                sessionStates[deviceID] = .mirroring
                appendLog("[\(session.device.logLabel)] 已收到手机画面，投屏窗口已就绪。")
            }
        }
        session.pendingOutput[stream] = Data(buffer.suffix(4096))
    }

    private func handleTermination(_ process: Process, deviceID: AndroidDevice.ID, token: UUID) {
        guard let session = runningSessions[deviceID], session.token == token else { return }
        for data in session.pendingOutput.values where !data.isEmpty {
            appendLog("[\(session.device.logLabel)] \(String(decoding: data, as: UTF8.self))")
        }
        runningSessions[deviceID] = nil

        if case .failed = sessionStates[deviceID] {
            return
        }
        if session.stopRequested || process.terminationStatus == 0 {
            sessionStates[deviceID] = .idle
            appendLog("[\(session.device.logLabel)] 投屏窗口已关闭。")
        } else {
            failDevice(deviceID, message: "连接中断或投屏组件退出（状态码 \(process.terminationStatus)）。请检查 USB 连接后重试。")
        }
    }

    private func failDevice(_ deviceID: AndroidDevice.ID, message: String) {
        sessionStates[deviceID] = .failed(message)
        logsExpanded = true
        let name = sessionDevices[deviceID]?.logLabel ?? deviceID
        appendLog("[\(name)] \(message)")
    }

    private func failGlobally(_ message: String) {
        globalErrorMessage = message
        logsExpanded = true
        appendLog(message)
    }

    private func appendLog(_ line: String) {
        let trimmed = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        guard !trimmed.isEmpty else { return }
        if logLines.last != trimmed { logLines.append(trimmed) }
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

}

private final class RunningMirrorSession {
    let device: AndroidDevice
    let token: UUID
    let process: Process
    let outputPipe: Pipe
    let errorPipe: Pipe
    var stopRequested = false
    var pendingOutput: [String: Data] = [:]

    init(device: AndroidDevice, token: UUID, process: Process, outputPipe: Pipe, errorPipe: Pipe) {
        self.device = device
        self.token = token
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }
}
