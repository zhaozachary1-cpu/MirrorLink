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
    @Published var qualityProfile: MirrorQualityProfile {
        didSet { preferences.set(qualityProfile.rawValue, forKey: MirrorQualityProfile.preferenceKey) }
    }

    let paths: ToolPaths?

    @Published private var runningSessions: [AndroidDevice.ID: RunningMirrorSession] = [:]
    @Published private var sessionDevices: [AndroidDevice.ID: AndroidDevice] = [:]
    @Published private var videoStatuses: [AndroidDevice.ID: MirrorVideoStatus] = [:]
    private let preferences: UserDefaults
    private let startupTimeout: TimeInterval
    private let snapshotProvider: (ToolPaths) -> ADBSnapshot
    private var shuttingDown = false
    private var hasResolvedInitialSelection = false
    private var refreshRequested = false

    init(
        paths: ToolPaths? = ToolPaths.discover(),
        startupTimeout: TimeInterval = 25,
        preferences: UserDefaults = .standard,
        snapshotProvider: @escaping (ToolPaths) -> ADBSnapshot = { ADBService(paths: $0).snapshot() }
    ) {
        self.paths = paths
        self.preferences = preferences
        self.qualityProfile = .restored(from: preferences.string(forKey: MirrorQualityProfile.preferenceKey))
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
            // A live process remains pinned to the route with which it started.
            if runningSessions[device.id] == nil { visible[device.id] = device }
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

    func videoStatus(for deviceID: AndroidDevice.ID) -> MirrorVideoStatus? {
        videoStatuses[deviceID]
    }

    func isRestartPending(for deviceID: AndroidDevice.ID) -> Bool {
        runningSessions[deviceID]?.restartRequest != nil
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
        guard !shuttingDown else { return }
        if isRefreshing {
            if !silent { refreshRequested = true }
            return
        }
        guard let paths, paths.isUsable else {
            toolchainAvailable = false
            if !silent { appendLog("刷新失败：应用内置工具不存在。") }
            return
        }

        isRefreshing = true
        if !silent { appendLog("正在扫描 USB / Wi-Fi 设备…") }
        let provider = snapshotProvider
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = provider(paths)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                guard !self.shuttingDown else { return }

                let resolvedDevices = self.reconcileDeviceIdentities(snapshot.devices)
                let changed = self.devices != resolvedDevices
                self.devices = resolvedDevices
                self.lastRefresh = Date()
                self.toolchainAvailable = paths.isUsable
                for diagnostic in snapshot.diagnostics { self.appendLog(diagnostic) }

                // Remember explicit choices for this app run, including across
                // reconnects. A refresh never undoes Clear Selection or starts a phone.
                if !self.hasResolvedInitialSelection && !resolvedDevices.isEmpty {
                    self.hasResolvedInitialSelection = true
                    let ready = resolvedDevices.filter { $0.state == .ready }
                    if ready.count == 1 {
                        self.selectedDeviceIDs = [ready[0].id]
                    } else if resolvedDevices.count == 1 {
                        self.selectedDeviceIDs = [resolvedDevices[0].id]
                    }
                }

                if changed || !silent {
                    self.appendLog(resolvedDevices.isEmpty ? "没有发现已连接设备。可使用 USB 或“无线连接”。" : "发现 \(resolvedDevices.count) 台设备（USB / Wi-Fi）。")
                }
                if self.refreshRequested {
                    self.refreshRequested = false
                    self.refresh()
                }
            }
        }
    }

    /// Only called after the wireless service verifies the exact target as ready.
    func connectAndMirror(_ device: AndroidDevice) {
        guard !shuttingDown, device.isWireless, device.state == .ready else { return }
        guard let device = reconcileDeviceIdentities([device]).first else { return }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        setDeviceSelected(device.id, isSelected: true)
        if let running = runningSessions[device.id], running.device.serial != device.serial {
            appendLog("\(device.displayName) 已有投屏窗口，仍使用 \(running.device.transport)。如需切到 Wi-Fi，请先停止该窗口再开始。")
        } else {
            startMirroring(for: device.id)
        }
        refresh()
    }

    /// A transient getprop failure must not turn one phone into a second row or
    /// orphan its running process. Learn identity without changing process keys.
    private func reconcileDeviceIdentities(_ incoming: [AndroidDevice]) -> [AndroidDevice] {
        func physicalID(_ device: AndroidDevice) -> String? {
            device.hardwareSerial ?? (device.isWireless ? nil : device.serial)
        }
        var known = sessionDevices.values.sorted {
            (runningSessions[$0.id] != nil ? 0 : 1) < (runningSessions[$1.id] != nil ? 0 : 1)
        } + devices
        for index in known.indices {
            guard physicalID(known[index]) == nil,
                  let learned = incoming.first(where: { $0.serial == known[index].serial && $0.hardwareSerial != nil }) else { continue }
            let stableID = known[index].id
            known[index].sessionIdentity = stableID
            known[index].hardwareSerial = learned.hardwareSerial
            if sessionDevices[stableID] != nil { sessionDevices[stableID] = known[index] }
        }

        var resolved: [AndroidDevice] = []
        for var device in incoming {
            let physical = physicalID(device)
            let match = known.first(where: { candidate in
                if let physical { return physicalID(candidate) == physical }
                return candidate.serial == device.serial
            })
            if let match {
                device.sessionIdentity = match.id
                if device.hardwareSerial == nil { device.hardwareSerial = match.hardwareSerial }
            }
            if let index = resolved.firstIndex(where: { $0.id == device.id }) {
                resolved[index] = ADBDeviceIdentity.preferred(resolved[index], device)
            } else { resolved.append(device) }
        }
        return resolved
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
            failGlobally(device.state == .unauthorized ? "请解锁手机并允许调试；无线设备请确认配对授权。" : "设备当前不可用：\(device.state.title)。")
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

    /// An explicit restart, never an automatic response to a quiet/static
    /// screen. Reap the old child before starting its replacement.
    func restartMirroring(for deviceID: AndroidDevice.ID) {
        guard !shuttingDown, let session = runningSessions[deviceID],
              !session.stopRequested else { return }
        guard let device = connectedDevice(for: deviceID), device.state == .ready else {
            appendLog("\(session.device.logLabel) 当前连接不可用，请刷新后重试。")
            return
        }
        stopMirroring(for: deviceID, appendingLog: false)
        session.restartRequest = (device, qualityProfile)
        appendLog("正在重新投屏 \(device.logLabel)，将使用\(qualityProfile.title)；其他设备不受影响。")
    }

    // Called synchronously on application termination, so no child outlives Quit.
    // Never kill an ADB daemon or another app's scrcpy session.
    func shutdown() {
        shuttingDown = true
        let sessions = Array(runningSessions.values)
        for session in sessions {
            session.restartRequest = nil
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

    private func startSession(for device: AndroidDevice, paths: ToolPaths, quality: MirrorQualityProfile? = nil) {
        let profile = quality ?? qualityProfile
        let requestedVideo = MirrorVideoStatus(profile: profile, isWireless: device.isWireless)
        videoStatuses[device.id] = requestedVideo
        let command = ScrcpyCommand(paths: paths)
        let token = UUID()
        let process = Process()
        let output: SessionLogStream
        let errors: SessionLogStream
        do {
            output = try SessionLogStream(lineBuffered: true)
            errors = try SessionLogStream(lineBuffered: false)
        } catch {
            sessionDevices[device.id] = device
            failDevice(device.id, message: "无法创建投屏日志通道：\(error.localizedDescription)")
            return
        }
        let readers = DispatchGroup()
        process.executableURL = paths.scrcpy
        process.arguments = command.arguments(for: device, quality: profile)
        process.standardOutput = output.childWriter
        process.standardError = errors.childWriter
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in command.environment(for: device) { environment[key] = value }
        process.environment = environment
        process.currentDirectoryURL = paths.root

        let session = RunningMirrorSession(
            device: device,
            token: token,
            process: process,
            logStreams: [output, errors]
        )
        runningSessions[device.id] = session
        sessionDevices[device.id] = device
        sessionStates[device.id] = .starting
        appendLog("正在启动 \(device.logLabel) 的投屏窗口…")
        appendLog("[\(device.logLabel)] 画质请求：\(requestedVideo.configurationSummary)。禁止出错后自动降低分辨率。")

        // Register before run(): even an immediately failing child must drain
        // both output streams before we publish its final state.
        readers.enter()
        readers.enter()

        process.terminationHandler = { [weak self] process in
            output.processDidExit()
            errors.processDidExit()
            readers.notify(queue: .global(qos: .utility)) {
                DispatchQueue.main.async {
                    self?.handleTermination(process, deviceID: device.id, token: token)
                }
            }
        }

        do {
            try process.run()
            output.closeParentWriter()
            errors.closeParentWriter()
            for (channel, stream) in [(output, "stdout"), (errors, "stderr")] {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    defer { readers.leave() }
                    channel.readChunks { data in
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
                self.failDevice(device.id, message: device.isWireless
                    ? "启动超时：尚未收到手机画面。请检查 Wi-Fi 和无线调试；如端口变化，请重新无线连接。"
                    : "启动超时：尚未收到手机画面。请解锁手机、确认 USB 调试授权后重试。")
                self.terminateOwnedProcess(deviceID: device.id, token: token)
            }
        } catch {
            output.closeParentWriter()
            errors.closeParentWriter()
            readers.leave()
            readers.leave()
            process.terminationHandler = nil
            runningSessions[device.id] = nil
            failDevice(device.id, message: "启动失败：\(error.localizedDescription)")
        }
    }

    private func stopMirroring(for deviceID: AndroidDevice.ID, appendingLog: Bool) {
        guard let session = runningSessions[deviceID] else { return }
        session.restartRequest = nil
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
            if let size = VideoResolution.parse(logLine: line) {
                session.videoEncoderFailed = false
                videoStatuses[deviceID]?.receive(size)
                if sessionStates[deviceID] == .starting {
                    sessionStates[deviceID] = .mirroring
                    appendLog("[\(session.device.logLabel)] 已收到手机画面，投屏窗口已就绪。")
                }
            }
            if line == "[server] INFO: Applying video encoder constraints"
                || line.hasPrefix("[server] INFO: Retrying with -m") {
                videoStatuses[deviceID]?.noteEncoderConstraint()
            }
            if line.hasPrefix("[server] ERROR: Could not create default video encoder for ")
                || line.hasPrefix("[server] ERROR: Capture/encoding error:") {
                session.videoEncoderFailed = true
            }
            if line == "WARN: Device disconnected" { session.reportedDisconnect = true }
        }
        session.pendingOutput[stream] = Data(buffer.suffix(4096))
    }

    private func handleTermination(_ process: Process, deviceID: AndroidDevice.ID, token: UUID) {
        guard let session = runningSessions[deviceID], session.token == token else { return }
        for data in session.pendingOutput.values where !data.isEmpty {
            appendLog("[\(session.device.logLabel)] \(String(decoding: data, as: UTF8.self))")
        }
        runningSessions[deviceID] = nil

        if let restart = session.restartRequest, !shuttingDown {
            sessionStates[deviceID] = .idle
            guard let paths, paths.isUsable,
                  let device = connectedDevice(for: deviceID), device.state == .ready,
                  device.serial == restart.device.serial, device.adbSocket == restart.device.adbSocket else {
                failDevice(deviceID, message: "连接已变化，已取消重新投屏。请刷新设备后手动开始。")
                return
            }
            startSession(for: device, paths: paths, quality: restart.profile)
            return
        }

        if case .failed = sessionStates[deviceID] {
            return
        }
        if session.stopRequested || process.terminationStatus == 0 {
            sessionStates[deviceID] = .idle
            appendLog("[\(session.device.logLabel)] 投屏窗口已关闭。")
        } else {
            // scrcpy can recover at the same size without another Texture
            // line. A historical encoder error must not mask a later unplug.
            if session.videoEncoderFailed, videoStatuses[deviceID]?.initialResolution == nil,
               process.terminationStatus != 2, !session.reportedDisconnect {
                failDevice(deviceID, message: "视频采集或编码出错后投屏结束。请检查连接和手机负载，或选择“低负载兼容”后重试；本次未自动降低分辨率。")
                return
            }
            let advice = session.device.isWireless ? "请检查 Wi-Fi 和手机无线调试，端口变化后需重新无线连接。" : "请检查 USB 连接后重试。"
            failDevice(deviceID, message: "连接中断或投屏组件退出（状态码 \(process.terminationStatus)）。\(advice)")
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
    let logStreams: [SessionLogStream]
    var stopRequested = false
    var pendingOutput: [String: Data] = [:]
    var restartRequest: (device: AndroidDevice, profile: MirrorQualityProfile)?
    var videoEncoderFailed = false
    var reportedDisconnect = false

    init(device: AndroidDevice, token: UUID, process: Process, logStreams: [SessionLogStream]) {
        self.device = device
        self.token = token
        self.process = process
        self.logStreams = logStreams
    }
}
