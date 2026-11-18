import Combine
import Foundation
import Darwin
import AppKit

@MainActor
final class MirrorSessionStore: ObservableObject {
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var selectedDeviceIDs: Set<AndroidDevice.ID> = []
    @Published private(set) var sessionStates: [AndroidDevice.ID: MirrorSessionState] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var logLines: [String] = []
    @Published private(set) var toolchainAvailable = false
    @Published private(set) var isRefreshing = false
    @Published private var globalFailureMessage: LocalizedMessage?
    @Published var logsExpanded = false
    @Published var qualityProfile: MirrorQualityProfile {
        didSet { preferences.set(qualityProfile.rawValue, forKey: MirrorQualityProfile.preferenceKey) }
    }
    @Published var windowLayout: MirrorWindowLayout {
        didSet { preferences.set(windowLayout.rawValue, forKey: MirrorWindowLayout.preferenceKey) }
    }
    @Published private var savedDevices: [String: KnownDevice] = [:]
    @Published private var ephemeralPreferences: [String: DevicePreferences] = [:]
    @Published private var reconnectRequests: [String: ReconnectRequest] = [:]
    @Published private var recordingMessages: [String: LocalizedMessage] = [:]
    @Published private var completedRecordings: [String: URL] = [:]
    private var selectedIdentities: Set<String> = []
    private var cancelledRecoveryDevices: Set<String> = []
    private let reconnectDelays: [TimeInterval]
    private let layoutBounds: () -> CGRect
    private static let devicesKey = "MirrorLinkKnownDevices"
    private static let selectionKey = "MirrorLinkSelectedDevices"

    let paths: ToolPaths?
    var windowToolState: ((AndroidDevice) -> [String: Any])?
    var onWindowToolAction: ((MirrorWindowAction, AndroidDevice) -> Void)?
    var onWindowFileAction: ((MirrorWindowAction, URL, AndroidDevice) -> Void)?
    private var windowControlTimer: DispatchSourceTimer?
    private var windowRecordingFeedback: [String: String] = [:]

    @Published private var runningSessions: [AndroidDevice.ID: RunningMirrorSession] = [:]
    @Published private var sessionDevices: [AndroidDevice.ID: AndroidDevice] = [:]
    @Published private var videoStatuses: [AndroidDevice.ID: MirrorVideoStatus] = [:]
    // Visible failures resolve in the current language. The original String
    // state and historical log entries remain compatible with diagnostics.
    @Published private var failureMessages: [AndroidDevice.ID: LocalizedMessage] = [:]
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
        reconnectDelays: [TimeInterval] = [1, 3, 7],
        layoutBounds: @escaping () -> CGRect = {
            guard let primary = NSScreen.screens.first, let screen = NSScreen.main ?? NSScreen.screens.first else {
                return CGRect(x: 0, y: 30, width: 1280, height: 770)
            }
            let frame = screen.visibleFrame
            return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        },
        snapshotProvider: @escaping (ToolPaths) -> ADBSnapshot = { ADBService(paths: $0).snapshot() }
    ) {
        self.paths = paths
        self.preferences = preferences
        self.qualityProfile = .restored(from: preferences.string(forKey: MirrorQualityProfile.preferenceKey))
        self.windowLayout = MirrorWindowLayout(rawValue: preferences.string(forKey: MirrorWindowLayout.preferenceKey) ?? "") ?? .automatic
        self.reconnectDelays = Array(reconnectDelays.prefix(3)).map { max(0.01, $0) }
        self.layoutBounds = layoutBounds
        if let data = preferences.data(forKey: Self.devicesKey), let saved = try? JSONDecoder().decode([KnownDevice].self, from: data) {
            self.savedDevices = saved.reduce(into: [:]) { result, device in
                guard device.id.hasPrefix("hardware:"), device.id.count > 9 else { return }
                var value = device
                value.preferences = device.preferences.normalized
                result[device.id] = value
            }
        }
        self.selectedIdentities = Set(preferences.stringArray(forKey: Self.selectionKey) ?? [])
        self.hasResolvedInitialSelection = preferences.object(forKey: Self.selectionKey) != nil
        self.startupTimeout = startupTimeout
        self.snapshotProvider = snapshotProvider
        self.toolchainAvailable = paths?.isUsable == true
        appendLog(paths == nil ? L10n.tr("未找到应用内置投屏组件。") : L10n.tr("已加载应用内置 ADB / scrcpy。"))
    }

    var knownDevices: [KnownDevice] {
        savedDevices.values.sorted {
            if $0.preferences.favorite != $1.preferences.favorite { return $0.preferences.favorite }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func savedIdentity(for device: AndroidDevice) -> String? {
        if let identity = DevicePreferences.identity(for: device) { return identity }
        guard let raw = device.hardwareSerial ?? (device.isWireless ? nil : device.serial) else { return nil }
        let identity = "hardware:\(raw)"
        return savedDevices[identity] == nil ? nil : identity
    }

    func preferences(for device: AndroidDevice) -> DevicePreferences {
        if let identity = savedIdentity(for: device), let saved = savedDevices[identity] { return saved.preferences }
        return ephemeralPreferences[device.id] ?? DevicePreferences()
    }

    func prefs(for device: AndroidDevice) -> DevicePreferences { preferences(for: device) }
    func activePreferences(for deviceID: String) -> DevicePreferences? { runningSessions[deviceID]?.options }
    func isReadOnlySession(for deviceID: String) -> Bool { runningSessions[deviceID]?.options.presentationMode == true }
    func isPresentationMode(for device: AndroidDevice) -> Bool {
        preferences(for: device).presentationMode || isReadOnlySession(for: device.id)
    }

    func updatePreferences(for device: AndroidDevice, preferences value: DevicePreferences) {
        let normalized = value.normalized
        if let identity = savedIdentity(for: device) {
            savedDevices[identity] = KnownDevice(id: identity, model: device.displayName == device.serial ? "" : device.displayName,
                preferences: normalized, lastSeen: Date())
            persistSavedDevices()
        } else {
            // An unidentified wireless endpoint may have session-only options,
            // but may never opt into automatic recovery or persistent memory.
            var ephemeral = normalized
            ephemeral.autoReconnect = false
            ephemeral.favorite = false
            ephemeralPreferences[device.id] = ephemeral
        }
        if !normalized.autoReconnect { cancelReconnect(for: device.id) }
    }

    func updatePreferences(forKnownDeviceID id: String, preferences value: DevicePreferences) {
        guard var known = savedDevices[id] else { return }
        known.preferences = value.normalized
        savedDevices[id] = known
        persistSavedDevices()
        if !value.autoReconnect {
            for (deviceID, request) in reconnectRequests where request.identity == id { cancelReconnect(for: deviceID) }
        }
    }

    func forgetKnownDevice(_ id: String) {
        let affected = devices.filter { savedIdentity(for: $0) == id }.map(\.id)
        savedDevices[id] = nil
        selectedIdentities.remove(id)
        for (deviceID, request) in reconnectRequests where request.identity == id { cancelReconnect(for: deviceID) }
        for deviceID in affected { selectedDeviceIDs.remove(deviceID) }
        persistSavedDevices()
        persistSelection()
    }

    func displayName(for device: AndroidDevice) -> String {
        let options = preferences(for: device)
        if !options.nickname.isEmpty { return options.nickname }
        if (options.presentationMode || isReadOnlySession(for: device.id)) && device.displayName == device.serial { return L10n.tr("Android 手机") }
        return device.displayName
    }

    func displaySerial(for device: AndroidDevice) -> String? {
        (preferences(for: device).presentationMode || isReadOnlySession(for: device.id)) ? nil : device.serial
    }

    private func persistSavedDevices() {
        if let data = try? JSONEncoder().encode(Array(savedDevices.values)) { preferences.set(data, forKey: Self.devicesKey) }
    }

    private func persistSelection() {
        preferences.set(Array(selectedIdentities).sorted(), forKey: Self.selectionKey)
    }

    private func remember(_ devices: [AndroidDevice]) {
        var changed = false
        let previousSelection = selectedIdentities
        for device in devices {
            guard let identity = DevicePreferences.identity(for: device) else { continue }
            let options = savedDevices[identity]?.preferences ?? ephemeralPreferences[device.id] ?? DevicePreferences()
            let model = device.displayName == device.serial ? "" : device.displayName
            if savedDevices[identity]?.model != model || savedDevices[identity]?.preferences != options
                || Date().timeIntervalSince(savedDevices[identity]?.lastSeen ?? .distantPast) >= 60 {
                savedDevices[identity] = KnownDevice(id: identity, model: model, preferences: options, lastSeen: Date())
                changed = true
            }
            if selectedDeviceIDs.contains(device.id) { selectedIdentities.insert(identity) }
            if selectedIdentities.contains(identity) { selectedDeviceIDs.insert(device.id) }
        }
        if changed { persistSavedDevices() }
        if previousSelection != selectedIdentities { persistSelection() }
    }

    var hasPendingReconnect: Bool { !reconnectRequests.isEmpty }

    func reconnectStatus(for deviceID: String) -> String? {
        guard let request = reconnectRequests[deviceID] else { return nil }
        return L10n.tr("等待恢复连接（%@/%@），可随时取消。", String(request.attempt + 1), String(reconnectDelays.count))
    }

    func cancelReconnect(for deviceID: String) {
        let cancelled = reconnectRequests.removeValue(forKey: deviceID)
        cancelledRecoveryDevices.insert(deviceID)
        if cancelled != nil, let session = runningSessions[deviceID], session.reconnect != nil,
           sessionStates[deviceID] == .starting {
            session.stopRequested = true
            sessionStates[deviceID] = .stopping
            terminateOwnedProcess(deviceID: deviceID, token: session.token)
        }
    }

    func recordingURL(for deviceID: String) -> URL? {
        runningSessions[deviceID]?.recording?.destination ?? runningSessions[deviceID]?.restartRequest?.recording?.destination
    }
    func isRecording(for deviceID: String) -> Bool { recordingURL(for: deviceID) != nil }
    func lastRecordingURL(for deviceID: String) -> URL? { completedRecordings[deviceID] }
    func recordingMessage(for deviceID: String) -> String? { recordingMessages[deviceID]?.resolved }

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
            (.mirroring, "%@ 台正在投屏"), (.starting, "%@ 台正在启动"), (.stopping, "%@ 台正在停止")
        ]
        var parts = counts.compactMap { state, format -> String? in
            let count = sessionStates.values.filter { $0 == state }.count
            return count == 0 ? nil : L10n.tr(format, String(count))
        }
        let failures = sessionStates.values.filter(\.isFailure).count
        if failures > 0 { parts.append(L10n.tr("%@ 台失败", String(failures))) }
        return parts.isEmpty ? L10n.tr("尚未开始投屏") : parts.joined(separator: " · ")
    }

    var globalErrorMessage: String? { globalFailureMessage?.resolved }

    var isMirroring: Bool {
        !runningSessions.isEmpty
    }

    var canStart: Bool {
        toolchainAvailable
            && !shuttingDown
            && startableSelectedCount > 0
    }

    var sessionState: MirrorSessionState {
        let states = sessionStates.keys.map { resolvedSessionState(for: $0) }
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
        resolvedSessionState(for: device.id)
    }

    private func resolvedSessionState(for deviceID: AndroidDevice.ID) -> MirrorSessionState {
        let state = sessionStates[deviceID] ?? .idle
        if case .failed = state, let message = failureMessages[deviceID] {
            return .failed(message.resolved)
        }
        return state
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
        if let device = devices.first(where: { $0.id == deviceID }) ?? sessionDevices[deviceID], let identity = savedIdentity(for: device) {
            if isSelected { selectedIdentities.insert(identity) } else { selectedIdentities.remove(identity) }
        }
        persistSelection()
    }

    func selectAllReadyDevices() {
        hasResolvedInitialSelection = true
        selectedDeviceIDs = Set(readyDevices.map(\.id))
        selectedIdentities = Set(readyDevices.compactMap { savedIdentity(for: $0) })
        persistSelection()
    }

    func clearDeviceSelection() {
        hasResolvedInitialSelection = true
        selectedDeviceIDs.removeAll()
        selectedIdentities.removeAll()
        persistSelection()
    }

    func refresh(silent: Bool = false) {
        guard !shuttingDown else { return }
        if isRefreshing {
            if !silent { refreshRequested = true }
            return
        }
        guard let paths, paths.isUsable else {
            toolchainAvailable = false
            if !silent { appendLog(L10n.tr("刷新失败：应用内置工具不存在。")) }
            return
        }

        isRefreshing = true
        if !silent { appendLog(L10n.tr("正在扫描 USB / Wi-Fi 设备…")) }
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
                self.remember(resolvedDevices)

                if changed || !silent {
                    self.appendLog(resolvedDevices.isEmpty ? L10n.tr("没有发现已连接设备。可使用 USB 或“无线连接”。") : L10n.tr("发现 %@ 台设备（USB / Wi-Fi）。", String(resolvedDevices.count)))
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
        remember([device])
        if let running = runningSessions[device.id], running.device.serial != device.serial {
            appendLog(L10n.tr("%@ 已有投屏窗口，仍使用 %@。如需切到 Wi-Fi，请先停止该窗口再开始。", device.displayName, running.device.transport))
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
            failGlobally(L10n.message("无法启动：应用内置工具不存在。"))
            return
        }

        let selected = selectedDevices
        guard !selected.isEmpty else {
            failGlobally(L10n.message("请先勾选至少一台设备。"))
            return
        }

        globalFailureMessage = nil
        for device in selected where device.state != .ready {
            appendLog(L10n.tr("跳过 %@：设备当前不可用（%@）。", device.logLabel, device.state.title))
        }

        let readyToStart = selected.filter { device in
            device.state == .ready && !isMirroring(for: device.id)
        }
        guard !readyToStart.isEmpty else {
            if selected.contains(where: { isMirroring(for: $0.id) }) {
                appendLog(L10n.tr("所选设备已经在投屏中。"))
            } else {
                failGlobally(L10n.message("所选设备中没有已连接且已授权的手机。"))
            }
            return
        }

        let count = runningSessions.count + readyToStart.count
        let firstIndex = runningSessions.count
        let screen = layoutBounds()
        for (index, device) in readyToStart.enumerated() {
            cancelReconnect(for: device.id)
            cancelledRecoveryDevices.remove(device.id)
            startSession(for: device, paths: paths,
                placement: windowLayout.placement(index: firstIndex + index, count: count, screen: screen))
        }
    }

    func startMirroring(for deviceID: AndroidDevice.ID) {
        guard !shuttingDown else { return }
        guard let paths, paths.isUsable else {
            failGlobally(L10n.message("无法启动：应用内置工具不存在。"))
            return
        }
        guard let device = devices.first(where: { $0.id == deviceID }) else {
            failGlobally(L10n.message("找不到要投屏的设备，请刷新设备列表。"))
            return
        }
        guard device.state == .ready else {
            if device.state == .unauthorized {
                failGlobally(L10n.message("请解锁手机并允许调试；无线设备请确认配对授权。"))
            } else if device.state == .offline {
                failGlobally(L10n.message("设备处于离线状态，请检查连接后重试。"))
            } else {
                failGlobally(L10n.message("无法确认设备状态，请检查连接后重试。"))
            }
            return
        }
        guard !isMirroring(for: device.id) else {
            appendLog(L10n.tr("%@ 已经在投屏中。", device.logLabel))
            return
        }

        globalFailureMessage = nil
        cancelReconnect(for: deviceID)
        cancelledRecoveryDevices.remove(deviceID)
        startSession(for: device, paths: paths)
    }

    func stopMirroring() {
        cancelledRecoveryDevices.formUnion(reconnectRequests.keys)
        reconnectRequests.removeAll()
        let activeIDs = Array(runningSessions.keys)
        guard !activeIDs.isEmpty else { return }
        appendLog(L10n.tr("正在停止 %@ 个投屏窗口…", String(activeIDs.count)))
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
            appendLog(L10n.tr("%@ 当前连接不可用，请刷新后重试。", session.device.logLabel))
            return
        }
        let options = preferences(for: device)
        let profile = options.qualityProfile ?? qualityProfile
        stopMirroring(for: deviceID, appendingLog: false)
        cancelledRecoveryDevices.remove(deviceID)
        // Restarting a recording closes that file; it never reuses/overwrites it.
        session.restartRequest = SessionRestart(device: device, profile: profile, options: options, placement: session.placement, recording: nil)
        appendLog(L10n.tr("正在重新投屏 %@，将使用%@；其他设备不受影响。", device.logLabel, profile.title))
    }

    func startRecording(for deviceID: String, to destination: URL) {
        guard !shuttingDown, let paths, paths.isUsable,
              let device = runningSessions[deviceID]?.device ?? connectedDevice(for: deviceID), device.state == .ready,
              !isRecording(for: deviceID), runningSessions[deviceID]?.stopRequested != true else { return }
        do {
            let recording = try RecordingJob(destination: destination)
            let options = preferences(for: device)
            let profile = options.qualityProfile ?? qualityProfile
            recordingMessages[deviceID] = L10n.message("准备录屏；本台投屏会重新启动，其他手机不受影响。")
            completedRecordings[deviceID] = nil
            cancelReconnect(for: deviceID)
            cancelledRecoveryDevices.remove(deviceID)
            if let session = runningSessions[deviceID] {
                stopMirroring(for: deviceID, appendingLog: false)
                cancelledRecoveryDevices.remove(deviceID)
                session.restartRequest = SessionRestart(device: device, profile: profile, options: options, placement: session.placement, recording: recording)
            } else {
                startSession(for: device, paths: paths, quality: profile, options: options, recording: recording)
            }
        } catch {
            recordingMessages[deviceID] = L10n.message("无法开始录屏：%@", error.localizedDescription)
        }
    }

    func stopRecording(for deviceID: String) {
        guard let session = runningSessions[deviceID], session.recording != nil || session.restartRequest?.recording != nil else { return }
        recordingMessages[deviceID] = L10n.message("正在保存录屏，完成后重新打开本台投屏。")
        if let pending = session.restartRequest?.recording { pending.cancelBeforeStart() }
        let device: AndroidDevice? = session.device
        stopMirroring(for: deviceID, appendingLog: false)
        if let device, device.state == .ready {
            cancelledRecoveryDevices.remove(deviceID)
            let options = preferences(for: device)
            session.restartRequest = SessionRestart(device: device, profile: options.qualityProfile ?? qualityProfile,
                options: options, placement: session.placement, recording: nil)
        }
    }

    // Called synchronously on application termination, so no child outlives Quit.
    // Never kill an ADB daemon or another app's scrcpy session.
    func shutdown() {
        shuttingDown = true
        windowControlTimer?.cancel(); windowControlTimer = nil
        reconnectRequests.removeAll()
        let sessions = Array(runningSessions.values)
        for session in sessions {
            session.controls?.close()
            session.restartRequest?.recording?.cancelBeforeStart()
            session.restartRequest = nil
            session.stopRequested = true
            failureMessages[session.device.id] = nil
            sessionStates[session.device.id] = .stopping
            if session.process.isRunning {
                if session.recording != nil { kill(session.process.processIdentifier, SIGINT) }
                else { session.process.terminate() }
            }
        }

        let deadline = Date().addingTimeInterval(sessions.contains { $0.recording != nil } ? 10 : 1.5)
        while sessions.contains(where: { $0.process.isRunning }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        for session in sessions where session.process.isRunning {
            kill(session.process.processIdentifier, SIGKILL)
        }
        for session in sessions where session.recording != nil {
            _ = session.readers.wait(timeout: .now() + 0.75)
            finalizeRecording(session)
        }
    }

    func clearLogs() {
        logLines.removeAll()
        globalFailureMessage = nil
    }

    private func startSession(for device: AndroidDevice, paths: ToolPaths, quality: MirrorQualityProfile? = nil,
                              options: DevicePreferences? = nil, placement: MirrorWindowPlacement? = nil,
                              recording: RecordingJob? = nil, reconnect: ReconnectRequest? = nil) {
        failureMessages[device.id] = nil
        let options = options ?? preferences(for: device)
        let profile = quality ?? options.qualityProfile ?? qualityProfile
        let requestedVideo = MirrorVideoStatus(profile: profile, isWireless: device.isWireless)
        videoStatuses[device.id] = requestedVideo
        let command = ScrcpyCommand(paths: paths)
        let token = UUID()
        let process = Process()
        let controls: MirrorWindowChannel
        let output: SessionLogStream
        let errors: SessionLogStream
        do {
            controls = try MirrorWindowChannel()
            output = try SessionLogStream(lineBuffered: true)
            errors = try SessionLogStream(lineBuffered: false)
        } catch {
            recording?.cancelBeforeStart()
            if recording != nil { recordingMessages[device.id] = L10n.message("录屏未开始，未生成完成文件。") }
            reconnectRequests[device.id] = nil
            sessionDevices[device.id] = device
            failDevice(device.id, message: L10n.message("无法创建投屏日志通道：%@", error.localizedDescription))
            return
        }
        let readers = DispatchGroup()
        process.executableURL = paths.scrcpy
        let placement = placement ?? windowLayout.placement(index: runningSessions.count, count: runningSessions.count + 1, screen: layoutBounds())
        process.arguments = command.arguments(for: device, quality: profile, preferences: options, placement: placement, recordingURL: recording?.temporaryURL)
        process.standardOutput = output.childWriter
        process.standardError = errors.childWriter
        process.standardInput = controls.input
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in command.environment(for: device) { environment[key] = value }
        environment["MIRRORLINK_WINDOW_CONTROLS"] = "1"
        process.environment = environment
        process.currentDirectoryURL = paths.root

        let session = RunningMirrorSession(
            device: device,
            token: token,
            process: process,
            logStreams: [output, errors], readers: readers, options: options, placement: placement,
            recording: recording, reconnect: reconnect, controls: controls
        )
        runningSessions[device.id] = session
        controls.onRequest = { [weak self] request in
            self?.handleWindowRequest(request, deviceID: device.id, token: token)
        }
        startWindowControlUpdates()
        sessionDevices[device.id] = device
        sessionStates[device.id] = .starting
        appendLog(L10n.tr("正在启动 %@ 的投屏窗口…", device.logLabel))
        appendLog(L10n.tr("[%@] 画质请求：%@。禁止出错后自动降低分辨率。", device.logLabel, requestedVideo.configurationSummary))

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
            controls.childDidLaunch()
            output.closeParentWriter()
            errors.closeParentWriter()
            for (channel, stream) in [(output, "stdout"), (errors, "stderr")] {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    defer { readers.leave() }
                    channel.readChunks { data in
                        recording?.observe(data, stream: stream)
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
                    ? L10n.message("启动超时：尚未收到手机画面。请检查 Wi-Fi 和无线调试；如端口变化，请重新无线连接。")
                    : L10n.message("启动超时：尚未收到手机画面。请解锁手机、确认 USB 调试授权后重试。"))
                self.terminateOwnedProcess(deviceID: device.id, token: token)
            }
        } catch {
            output.closeParentWriter()
            errors.closeParentWriter()
            readers.leave()
            readers.leave()
            process.terminationHandler = nil
            controls.close()
            runningSessions[device.id] = nil
            recording?.cancelBeforeStart()
            if recording != nil { recordingMessages[device.id] = L10n.message("录屏未开始，未生成完成文件。") }
            failDevice(device.id, message: L10n.message("启动失败：%@", error.localizedDescription))
            if reconnect != nil { scheduleReconnect(after: session) }
        }
    }

    private func stopMirroring(for deviceID: AndroidDevice.ID, appendingLog: Bool) {
        cancelReconnect(for: deviceID)
        guard let session = runningSessions[deviceID] else { return }
        if let pending = session.restartRequest?.recording {
            pending.cancelBeforeStart()
            recordingMessages[deviceID] = L10n.message("录屏未开始，未生成完成文件。")
        }
        session.restartRequest = nil
        session.stopRequested = true
        updateWindowControls(session)
        failureMessages[deviceID] = nil
        sessionStates[deviceID] = .stopping
        if appendingLog { appendLog(L10n.tr("正在停止 %@ 的投屏…", session.device.logLabel)) }
        terminateOwnedProcess(deviceID: deviceID, token: session.token)
    }

    private func terminateOwnedProcess(deviceID: AndroidDevice.ID, token: UUID) {
        guard let session = runningSessions[deviceID], session.token == token, session.process.isRunning else { return }
        let process = session.process
        if session.recording != nil {
            recordingMessages[deviceID] = L10n.message("正在保存录屏…")
            kill(process.processIdentifier, SIGINT)
        } else { process.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (session.recording == nil ? 2 : 10)) { [weak self] in
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
                    if session.reconnect != nil { reconnectRequests[deviceID] = nil }
                    if session.recording != nil { recordingMessages[deviceID] = L10n.message("正在录屏，停止后将保存 MP4。") }
                    appendLog(L10n.tr("[%@] 已收到手机画面，投屏窗口已就绪。", session.device.logLabel))
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
        session.controls?.close()
        for data in session.pendingOutput.values where !data.isEmpty {
            appendLog("[\(session.device.logLabel)] \(String(decoding: data, as: UTF8.self))")
        }
        runningSessions[deviceID] = nil
        finalizeRecording(session)

        if let restart = session.restartRequest, !shuttingDown {
            sessionStates[deviceID] = .idle
            guard let paths, paths.isUsable,
                  let device = connectedDevice(for: deviceID), device.state == .ready,
                  device.serial == restart.device.serial, device.adbSocket == restart.device.adbSocket else {
                restart.recording?.cancelBeforeStart()
                if restart.recording != nil { recordingMessages[deviceID] = L10n.message("连接已变化，录屏未开始。") }
                failDevice(deviceID, message: L10n.message("连接已变化，已取消重新投屏。请刷新设备后手动开始。"))
                return
            }
            startSession(for: device, paths: paths, quality: restart.profile, options: restart.options,
                placement: restart.placement, recording: restart.recording)
            return
        }

        let disconnected = process.terminationStatus == 2 || session.reportedDisconnect
        if !session.stopRequested && !shuttingDown && process.terminationStatus != 0
            && (disconnected || (session.reconnect != nil && videoStatuses[deviceID]?.initialResolution == nil)) {
            if scheduleReconnect(after: session) { return }
        }

        if case .failed = sessionStates[deviceID] {
            return
        }
        if session.stopRequested || process.terminationStatus == 0 {
            failureMessages[deviceID] = nil
            sessionStates[deviceID] = .idle
            appendLog(L10n.tr("[%@] 投屏窗口已关闭。", session.device.logLabel))
        } else {
            // scrcpy can recover at the same size without another Texture
            // line. A historical encoder error must not mask a later unplug.
            if session.videoEncoderFailed, videoStatuses[deviceID]?.initialResolution == nil,
               process.terminationStatus != 2, !session.reportedDisconnect {
                failDevice(deviceID, message: L10n.message("视频采集或编码出错后投屏结束。请检查连接和手机负载，或选择“低负载兼容”后重试；本次未自动降低分辨率。"))
                return
            }
            let message = session.device.isWireless
                ? L10n.message("连接中断或投屏组件退出（状态码 %@）。请检查 Wi-Fi 和手机无线调试，端口变化后需重新无线连接。", String(process.terminationStatus))
                : L10n.message("连接中断或投屏组件退出（状态码 %@）。请检查 USB 连接后重试。", String(process.terminationStatus))
            failDevice(deviceID, message: message)
        }
    }

    private func finalizeRecording(_ session: RunningMirrorSession) {
        guard let recording = session.recording, let result = recording.finalize() else { return }
        switch result {
        case .completed(let url):
            completedRecordings[session.device.id] = url
            recordingMessages[session.device.id] = L10n.message("录屏已保存：%@", url.path)
        case .incomplete(let url):
            completedRecordings[session.device.id] = nil
            if let url {
                recordingMessages[session.device.id] = L10n.message("录屏未完整保存；临时文件保留在 %@，请检查后使用。", url.path)
            } else { recordingMessages[session.device.id] = L10n.message("录屏未完成，没有可用文件。") }
        }
    }

    @discardableResult
    private func scheduleReconnect(after session: RunningMirrorSession) -> Bool {
        let deviceID = session.device.id
        guard !shuttingDown, !cancelledRecoveryDevices.contains(deviceID), session.options.autoReconnect,
              let identity = DevicePreferences.identity(for: session.device),
              savedDevices[identity]?.preferences.autoReconnect == true else { return false }
        var request = session.reconnect ?? ReconnectRequest(identity: identity, device: session.device, placement: session.placement)
        guard request.attempt < reconnectDelays.count else {
            reconnectRequests[deviceID] = nil
            failDevice(deviceID, message: L10n.message("已尝试恢复连接 %@ 次，请检查连接后手动重试。", String(reconnectDelays.count)))
            return true
        }
        // A new token invalidates every older delayed callback for this device.
        request.token = UUID()
        reconnectRequests[deviceID] = request
        sessionStates[deviceID] = .failed(L10n.tr("连接中断，正在等待恢复。"))
        failureMessages[deviceID] = L10n.message("连接中断，正在等待恢复。")
        armReconnect(deviceID: deviceID, request: request)
        return true
    }

    private func armReconnect(deviceID: String, request: ReconnectRequest) {
        guard request.attempt < reconnectDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelays[request.attempt]) { [weak self] in
            guard let self, !self.shuttingDown, self.reconnectRequests[deviceID]?.token == request.token,
                  self.runningSessions[deviceID] == nil else { return }
            guard let paths = self.paths, paths.isUsable else {
                self.reconnectRequests[deviceID] = nil
                self.failDevice(deviceID, message: L10n.message("无法启动：应用内置工具不存在。"))
                return
            }
            let provider = self.snapshotProvider
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let snapshot = provider(paths)
                DispatchQueue.main.async {
                    guard let self, !self.shuttingDown,
                          self.reconnectRequests[deviceID]?.token == request.token,
                          self.savedDevices[request.identity]?.preferences.autoReconnect == true,
                          self.runningSessions[deviceID] == nil else { return }
                    var next = request
                    next.attempt += 1
                    let candidates = snapshot.rawRoutes.filter {
                        $0.state == .ready && DevicePreferences.identity(for: $0) == request.identity
                            && $0.transport == request.device.transport && $0.adbSocket == request.device.adbSocket
                    }
                    if let candidate = candidates.first {
                        var device = candidate
                        device.sessionIdentity = deviceID
                        self.devices.removeAll { $0.id == deviceID }
                        self.devices.append(device)
                        self.reconnectRequests[deviceID] = next
                        // Recovery starts a new process. Apply the latest saved
                        // choices (especially read-only mode), not stale options
                        // captured before the disconnect or the retry delay.
                        let options = self.savedDevices[request.identity]?.preferences ?? DevicePreferences()
                        self.startSession(for: device, paths: paths, quality: options.qualityProfile ?? self.qualityProfile,
                            options: options, placement: request.placement, reconnect: next)
                    } else if next.attempt < self.reconnectDelays.count {
                        self.reconnectRequests[deviceID] = next
                        self.armReconnect(deviceID: deviceID, request: next)
                    } else {
                        self.reconnectRequests[deviceID] = nil
                        self.failDevice(deviceID, message: L10n.message("已尝试恢复连接 %@ 次，请检查连接后手动重试。", String(self.reconnectDelays.count)))
                    }
                }
            }
        }
    }

    private func failDevice(_ deviceID: AndroidDevice.ID, message: LocalizedMessage) {
        failureMessages[deviceID] = message
        sessionStates[deviceID] = .failed(message.resolved)
        logsExpanded = true
        let name = sessionDevices[deviceID]?.logLabel ?? deviceID
        appendLog("[\(name)] \(message.resolved)")
    }

    private func failGlobally(_ message: LocalizedMessage) {
        globalFailureMessage = message
        logsExpanded = true
        appendLog(message.resolved)
    }

    private func appendLog(_ line: String) {
        let trimmed = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        guard !trimmed.isEmpty else { return }
        if logLines.last != trimmed { logLines.append(trimmed) }
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    private func startWindowControlUpdates() {
        guard windowControlTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.runningSessions.isEmpty {
                self.windowControlTimer?.cancel(); self.windowControlTimer = nil
                return
            }
            for session in self.runningSessions.values { self.updateWindowControls(session) }
        }
        windowControlTimer = timer
        timer.resume()
    }

    private func updateWindowControls(_ session: RunningMirrorSession, force: Bool = false) {
        let id = session.device.id
        let ready = !shuttingDown && !session.stopRequested && sessionStates[id] == .mirroring
        var state = windowToolState?(session.device) ?? [:]
        state["type"] = "state"
        state["ready"] = ready
        state["controlAllowed"] = ready && !isPresentationMode(for: session.device)
        state["recording"] = session.recording != nil
        state["recordAllowed"] = ready && session.restartRequest == nil
        state["recordingPath"] = completedRecordings[id]?.path ?? ""
        state["homeTitle"] = L10n.tr("返回桌面")
        state["drawerTitle"] = L10n.tr("应用列表")
        state["screenshotTitle"] = L10n.tr("保存截图")
        state["recordTitle"] = session.recording != nil ? L10n.tr("结束录屏") : L10n.tr("开始录屏…")
        state["moreTitle"] = L10n.tr("更多投屏操作")
        state["sendFileTitle"] = L10n.tr("发送文件…")
        state["installAPKTitle"] = L10n.tr("安装 APK…")
        state["chooseFileTitle"] = L10n.tr("选择要发送的文件")
        state["chooseAPKTitle"] = L10n.tr("选择要安装的 APK")
        state["installTitle"] = L10n.tr("确认安装所选 APK？")
        state["installExplanation"] = L10n.tr("将所选 APK 安装到 %@。不会覆盖已有应用；请确认文件来源。", displayName(for: session.device))
        state["installConfirm"] = L10n.tr("安装到这台设备")
        state["sendPrompt"] = L10n.tr("发送到手机")
        state["sendExplanation"] = L10n.tr("选择后直接发送到这台手机的 Download/MirrorLink 文件夹（最大 2 GB）。选择 APK 时将进入安装确认。")
        state["cancelOperationTitle"] = L10n.tr("取消操作")
        state["swipeTitle"] = L10n.tr("尝试上滑打开应用列表")
        state["showScreenshotTitle"] = L10n.tr("显示最近截图")
        state["showRecordingTitle"] = L10n.tr("显示最近录屏")
        state["statusTitle"] = L10n.tr("查看操作结果")
        state["startTitle"] = L10n.tr("开始这台设备的录屏？")
        state["startExplanation"] = L10n.tr("将启动或重新启动这台设备的投屏并开始录制，当前画面会短暂中断；其他手机不受影响。录屏可能包含手机上的私人内容。")
        state["startConfirm"] = L10n.tr("选择保存位置并录屏…")
        state["stopTitle"] = L10n.tr("结束录屏并继续投屏？")
        state["stopExplanation"] = L10n.tr("镜连将保存本次录屏，并重新打开这台设备的普通投屏窗口；其他手机不受影响。")
        state["stopConfirm"] = L10n.tr("保存并继续投屏")
        state["cancelTitle"] = L10n.tr("取消")
        state["saveRecordingTitle"] = L10n.tr("保存录屏")
        if let baseline = windowRecordingFeedback[id], baseline == (state["resultID"] as? String ?? ""),
           let message = recordingMessages[id] {
            state["status"] = message.resolved
            state["resultID"] = "recording-" + message.resolved
        }
        if let status = state["status"] as? String { state["status"] = String(status.prefix(700)) }
        session.controls?.sendState(state, force: force)
    }

    private func handleWindowRequest(_ request: MirrorWindowRequest, deviceID: String, token: UUID) {
        guard !shuttingDown, let session = runningSessions[deviceID], session.token == token,
              session.process.isRunning, !session.stopRequested else { return }
        if request.action == .ready { updateWindowControls(session, force: true); return }
        guard sessionStates[deviceID] == .mirroring, session.restartRequest == nil else { return }
        let state = windowToolState?(session.device) ?? [:]
        switch request.action {
        case .home, .drawer, .swipe:
            guard !isPresentationMode(for: session.device), !(state["busy"] as? Bool ?? false) else { return }
            onWindowToolAction?(request.action, session.device)
        case .screenshot:
            guard !(state["busy"] as? Bool ?? false) else { return }
            onWindowToolAction?(.screenshot, session.device)
        case .sendFile, .installAPK:
            guard !isPresentationMode(for: session.device), !(state["busy"] as? Bool ?? false),
                  let path = request.path, path.hasPrefix("/"), path.utf8.count < 4096,
                  !path.contains("\0") else { return }
            let url = URL(fileURLWithPath: path)
            guard (request.action == .installAPK) == (url.pathExtension.lowercased() == "apk") else { return }
            onWindowFileAction?(request.action, url, session.device)
        case .cancel:
            onWindowToolAction?(.cancel, session.device)
        case .recordStart:
            guard session.recording == nil, let path = request.path, path.hasPrefix("/"),
                  path.utf8.count < 4096, !path.contains("\0") else { return }
            windowRecordingFeedback[deviceID] = state["resultID"] as? String ?? ""
            startRecording(for: deviceID, to: URL(fileURLWithPath: path))
        case .recordStop:
            guard session.recording != nil else { return }
            windowRecordingFeedback[deviceID] = state["resultID"] as? String ?? ""
            stopRecording(for: deviceID)
        case .ready: break
        }
        updateWindowControls(session)
    }

}

@MainActor
private final class RunningMirrorSession {
    let device: AndroidDevice
    let token: UUID
    let process: Process
    let logStreams: [SessionLogStream]
    let readers: DispatchGroup
    let options: DevicePreferences
    let placement: MirrorWindowPlacement?
    let recording: RecordingJob?
    let reconnect: ReconnectRequest?
    let controls: MirrorWindowChannel?
    var stopRequested = false
    var pendingOutput: [String: Data] = [:]
    var restartRequest: SessionRestart?
    var videoEncoderFailed = false
    var reportedDisconnect = false

    init(device: AndroidDevice, token: UUID, process: Process, logStreams: [SessionLogStream], readers: DispatchGroup,
         options: DevicePreferences, placement: MirrorWindowPlacement?, recording: RecordingJob?, reconnect: ReconnectRequest?, controls: MirrorWindowChannel?) {
        self.device = device
        self.token = token
        self.process = process
        self.logStreams = logStreams
        self.readers = readers
        self.options = options
        self.placement = placement
        self.recording = recording
        self.reconnect = reconnect
        self.controls = controls
    }
}

private struct SessionRestart {
    let device: AndroidDevice
    let profile: MirrorQualityProfile
    let options: DevicePreferences
    let placement: MirrorWindowPlacement?
    let recording: RecordingJob?
}

private struct ReconnectRequest {
    var token = UUID()
    let identity: String
    let device: AndroidDevice
    let placement: MirrorWindowPlacement?
    var attempt = 0
}

/// scrcpy writes in a fresh private sibling directory. Publishing uses an
/// exclusive rename on macOS,
/// which refuses an existing destination even if another process created it
/// after the save panel closed. Failed/unfinished media are retained separately.
private final class RecordingJob: @unchecked Sendable {
    enum Result { case completed(URL), incomplete(URL?) }
    let destination: URL
    let temporaryURL: URL
    private let temporaryDirectory: URL
    private let lock = NSLock()
    private var pending: [String: Data] = [:]
    private var completed = false
    private var failed = false
    private var finalized = false

    init(destination: URL) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "mp4" else {
            throw NSError(domain: "MirrorLink.Recording", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.tr("请选择本地 MP4 文件保存位置。")])
        }
        self.destination = destination.standardizedFileURL
        var info = stat()
        guard lstat(self.destination.path, &info) != 0 && errno == ENOENT else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
        }
        temporaryDirectory = self.destination.deletingLastPathComponent().appendingPathComponent(".mirrorlink-recording-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(temporaryDirectory.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        temporaryURL = temporaryDirectory.appendingPathComponent("recording.mp4")
    }

    func observe(_ data: Data, stream: String) {
        lock.lock(); defer { lock.unlock() }
        var buffer = (pending[stream] ?? Data()) + data
        while let newline = buffer.firstIndex(of: 10) {
            inspect(String(decoding: buffer[..<newline], as: UTF8.self))
            buffer.removeSubrange(...newline)
        }
        pending[stream] = Data(buffer.suffix(8192))
    }

    private func inspect(_ line: String) {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if line == "INFO: Recording complete to mp4 file: \(temporaryURL.path)" { completed = true }
        if line == "ERROR: Recording failed to \(temporaryURL.path)" || line.contains("Recording stopped before headers were processed") { failed = true }
    }

    func cancelBeforeStart() {
        lock.lock(); defer { lock.unlock() }
        guard !finalized else { return }
        finalized = true
        // Only an empty directory created by this job can be removed here.
        _ = rmdir(temporaryDirectory.path)
    }

    func finalize() -> Result? {
        lock.lock(); defer { lock.unlock() }
        guard !finalized else { return nil }
        finalized = true
        for data in pending.values where !data.isEmpty { inspect(String(decoding: data, as: UTF8.self)) }
        let exists = FileManager.default.fileExists(atPath: temporaryURL.path)
        guard completed, !failed, Self.isFinalizedMP4(temporaryURL), renamex_np(temporaryURL.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            if !exists { _ = rmdir(temporaryDirectory.path) }
            return .incomplete(exists ? temporaryURL : nil)
        }
        _ = rmdir(temporaryDirectory.path)
        return .completed(destination)
    }

    private static func isFinalizedMP4(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 32,
              let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        let total = UInt64(info.st_size)
        var offset: UInt64 = 0
        var types = Set<String>()
        while offset + 8 <= total {
            guard (try? file.seek(toOffset: offset)) != nil,
                  let bytes = try? file.read(upToCount: 16), bytes.count >= 8 else { return false }
            let size32 = bytes.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let type = String(decoding: bytes[4..<8], as: UTF8.self)
            let size: UInt64
            if size32 == 1 {
                guard bytes.count >= 16 else { return false }
                size = bytes[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                guard size >= 16 else { return false }
            } else { size = size32 == 0 ? total - offset : size32 }
            guard size >= 8, size <= total - offset else { return false }
            if ["ftyp", "moov", "mdat"].contains(type), size > 8 { types.insert(type) }
            offset += size
        }
        return offset == total && types == Set(["ftyp", "moov", "mdat"])
    }
}
