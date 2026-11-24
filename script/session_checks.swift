import Combine
import Foundation
import Darwin

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private extension SessionChecks {
    func runQualityChecks() async throws {
        let originalLanguage = L10n.language
        defer { L10n.setLanguage(originalLanguage) }
        let preferences = makePreferences()
        preferences.set("unknown-old-profile", forKey: MirrorQualityProfile.preferenceKey)
        let preferenceSource = SnapshotSource()
        let preferenceStore = makeStore(preferenceSource, preferences: preferences)
        try check(preferenceStore.qualityProfile == .nativeClarity, "invalid persisted profile restores the native clarity default")
        preferenceStore.qualityProfile = .nativeSmooth
        try check(preferences.string(forKey: MirrorQualityProfile.preferenceKey) == MirrorQualityProfile.nativeSmooth.rawValue, "quality selection persists in an isolated preferences suite")
        let restored = makeStore(preferenceSource, preferences: preferences)
        try check(restored.qualityProfile == .nativeSmooth, "a new store restores the selected quality")

        let a = device("QUALITY-A", socket: "tcp:127.0.0.1:5038")
        let b = device("QUALITY-B")
        let source = SnapshotSource()
        source.set([a, b])
        let store = makeStore(source)
        var readyEvents = 0
        store.onMirrorWindowReady = { readyEvents += 1 }
        try await refresh(store)
        store.selectAllReadyDevices()
        store.startMirroring()
        try check(readyEvents == 0, "control window stays open until video readiness, not Process.run")
        try await wait("quality frames") { store.sessionState(for: a) == .mirroring && store.sessionState(for: b) == .mirroring }
        try check(readyEvents == 2, "each independently ready mirror requests control window closure once")
        try check(store.videoStatus(for: a.id)?.profile == .nativeClarity && store.videoStatus(for: a.id)?.resolution?.pixelCount == 2_592_000, "a session reports its actual first-frame dimensions and starting profile")
        let peerPID = launches(b.serial).last?["pid"] as? Int
        let firstPID = launches(a.serial).last?["pid"] as? Int
        let initialArguments = launches(a.serial).last?["arguments"] as? [String]
        let initialSocket = launches(a.serial).last?["socket"] as? String
        L10n.setLanguage(.english)
        try check(DeviceConnectionState.ready.title == "Connected" && store.sessionState(for: a).title == "Mirroring" && store.sessionSummary == "Mirroring: 2" && store.videoStatus(for: a.id)?.profile.title == "Native Clarity (Recommended)", "active device status, aggregate summary, and quality labels resolve in English")
        try check(store.runningCount == 2 && launches(a.serial).count == 1 && launches(b.serial).count == 1 && launches(a.serial).last?["pid"] as? Int == firstPID && launches(b.serial).last?["pid"] as? Int == peerPID && launches(a.serial).last?["arguments"] as? [String] == initialArguments && launches(a.serial).last?["socket"] as? String == initialSocket && store.videoStatus(for: a.id)?.profile == .nativeClarity, "switching language preserves both child processes, their routes, and active quality configuration")
        L10n.setLanguage(.simplifiedChinese)
        try check(store.sessionSummary == "2 台正在投屏" && store.videoStatus(for: a.id)?.profile.title == "原生超清（推荐）", "switching back restores Chinese status without restarting sessions")
        store.qualityProfile = .nativeSmooth
        try check(store.videoStatus(for: a.id)?.profile == .nativeClarity && store.videoStatus(for: b.id)?.profile == .nativeClarity && launches(a.serial).count == 1 && launches(b.serial).count == 1, "changing global quality neither relabels nor restarts active sessions")

        try write("log:INFO: Texture: 2400x1080", serial: a.serial, suffix: "command")
        try await wait("orientation update") { store.logLines.contains { $0.contains("Texture: 2400x1080") } }
        try check(readyEvents == 2, "rotation cannot close a reopened control window")
        try check(store.videoStatus(for: a.id)?.warning == nil && store.videoStatus(for: a.id)?.resolution?.pixelCount == 2_592_000, "rotation updates dimensions without a false clarity warning")
        try write("split-log:INFO: Texture: 720x1600", serial: a.serial, suffix: "command")
        try await wait("smaller video") { store.videoStatus(for: a.id)?.resolution?.pixelCount == 1_152_000 }
        try check(store.videoStatus(for: a.id)?.warning != nil && store.videoStatus(for: b.id)?.warning == nil, "a real resolution decrease warns only the affected device")
        try write("log:INFO: Texture: 1080x2400", serial: a.serial, suffix: "command")
        try await wait("native resolution returns") { store.videoStatus(for: a.id)?.resolution?.pixelCount == 2_592_000 }
        try check(store.videoStatus(for: a.id)?.warning == nil, "return to the baseline clears the resolution-loss warning")
        try write("log:[server] INFO: Applying video encoder constraints", serial: a.serial, suffix: "command")
        try await wait("encoder constraints surfaced") { store.videoStatus(for: a.id)?.warning != nil }
        try check(store.videoStatus(for: b.id)?.warning == nil, "server encoder adjustments are visible only on the relevant session")
        L10n.setLanguage(.english)
        try check(store.videoStatus(for: a.id)?.encoderNotice?.hasPrefix("The phone's encoder adjusted") == true, "an existing encoder notice follows the selected language")
        L10n.setLanguage(.simplifiedChinese)
        try write("", serial: a.serial, suffix: "command")

        store.restartMirroring(for: a.id)
        // The requested configuration belongs to this restart, even if another
        // setting is chosen while the old process drains its output.
        store.qualityProfile = .compatibility
        try await wait("single target quality restart") { launches(a.serial).count == 2 && store.sessionState(for: a) == .mirroring }
        let replacement = launches(a.serial).last!
        let replacementArguments = replacement["arguments"] as? [String] ?? []
        try check(store.videoStatus(for: a.id)?.profile == .nativeSmooth && replacementArguments.contains("--max-fps=60") && replacementArguments.contains("--max-size=0"), "restart captures the quality chosen when it was requested")
        try check(replacement["socket"] as? String == a.adbSocket && store.videoStatus(for: b.id)?.profile == .nativeClarity && launches(b.serial).count == 1 && launches(b.serial).last?["pid"] as? Int == peerPID, "single-device restart preserves its route and never restarts its peer")
        try check(store.runningCount == 2 && store.videoStatus(for: a.id)?.warning == nil, "restart replaces one owned child and clears old quality diagnostics")

        store.restartMirroring(for: a.id)
        let wasPending = store.isRestartPending(for: a.id)
        store.stopMirroring(for: a.id)
        try check(wasPending && !store.isRestartPending(for: a.id), "restart status is visible while queued and clears immediately when Stop cancels it")
        try await wait("cancel queued restart") { !store.isMirroring(for: a.id) }
        try await Task.sleep(nanoseconds: 120_000_000)
        try check(launches(a.serial).count == 2 && store.sessionState(for: a) == .idle && store.isMirroring(for: b.id), "Stop cancels a queued restart without affecting the peer")
        store.startMirroring(for: a.id)
        try await wait("start with newest saved profile") { store.sessionState(for: a) == .mirroring }
        let compatibilityArguments = launches(a.serial).last?["arguments"] as? [String] ?? []
        try check(store.videoStatus(for: a.id)?.profile == .compatibility && compatibilityArguments.contains("--max-size=1920") && compatibilityArguments.contains("--video-bit-rate=12M"), "a later manual start uses the current saved compatibility profile")
        store.restartMirroring(for: a.id)
        store.restartMirroring(for: b.id)
        store.stopMirroring()
        try await wait("cancel all queued restarts") { !store.isMirroring }
        try await Task.sleep(nanoseconds: 120_000_000)
        try check(launches(a.serial).count == 3 && launches(b.serial).count == 1, "Stop All cancels every pending restart")

        let changingRoute = device("QUALITY-ROUTE-CHANGED", socket: "tcp:127.0.0.1:5037")
        let routeSource = SnapshotSource()
        routeSource.set([changingRoute])
        let routeStore = makeStore(routeSource)
        try write("ignore-term", serial: changingRoute.serial, suffix: "mode")
        try await refresh(routeStore)
        routeStore.startMirroring()
        try await wait("route test frame") { routeStore.sessionState(for: changingRoute) == .mirroring }
        routeStore.restartMirroring(for: changingRoute.id)
        routeSource.set([device(changingRoute.serial, socket: "tcp:127.0.0.1:5038")])
        try await refresh(routeStore)
        try await wait("changed route cancels restart", timeout: 3.5) { !routeStore.isMirroring }
        try check(routeStore.sessionState(for: changingRoute).isFailure && launches(changingRoute.serial).count == 1 && routeStore.logLines.contains { $0.contains("连接已变化") }, "a delayed restart cannot silently switch to a newly discovered ADB route")

        let restartTimer = device("QUALITY-STALE-RESTART-TIMER")
        let timerSource = SnapshotSource()
        timerSource.set([restartTimer])
        let timerStore = makeStore(timerSource, timeout: 0.9)
        try write("silent", serial: restartTimer.serial, suffix: "mode")
        try await refresh(timerStore)
        timerStore.startMirroring()
        try await Task.sleep(nanoseconds: 350_000_000)
        timerStore.restartMirroring(for: restartTimer.id)
        try await wait("silent restarted process") { launches(restartTimer.serial).count == 2 }
        try await Task.sleep(nanoseconds: 600_000_000)
        try check(timerStore.sessionState(for: restartTimer) == .starting, "the old startup watchdog cannot fail a queued replacement session")
        try write("ready", serial: restartTimer.serial, suffix: "command")
        try await wait("restarted texture") { timerStore.sessionState(for: restartTimer) == .mirroring }
        timerStore.stopMirroring()
        try await wait("restarted timer fixture stops") { !timerStore.isMirroring }

        let malformed = device("MALFORMED-VIDEO-LOG")
        let malformedSource = SnapshotSource()
        malformedSource.set([malformed])
        let malformedStore = makeStore(malformedSource)
        try write("malformed-texture", serial: malformed.serial, suffix: "mode")
        try await refresh(malformedStore)
        malformedStore.startMirroring()
        try await wait("malformed log delivered") { malformedStore.logLines.contains { $0.contains("1080x2400 invalid") } }
        try check(malformedStore.sessionState(for: malformed) == .starting && malformedStore.videoStatus(for: malformed.id)?.resolution == nil, "invalid or error Texture text does not claim first-frame success")
        try write("split-log:INFO: Texture: 1080x2400", serial: malformed.serial, suffix: "command")
        try await wait("valid split video log") { malformedStore.sessionState(for: malformed) == .mirroring }
        try check(malformedStore.videoStatus(for: malformed.id)?.resolution?.pixelCount == 2_592_000, "a valid texture line split across reads sets video readiness")
        malformedStore.restartMirroring(for: malformed.id)
        malformedStore.shutdown()
        try await wait("quit cancels restart") { !malformedStore.isMirroring }
        try await Task.sleep(nanoseconds: 120_000_000)
        try check(launches(malformed.serial).count == 1, "Quit cancels a pending restart and cannot relaunch a child")

        let encoder = device("VIDEO-ENCODER-FAILURE")
        let encoderSource = SnapshotSource()
        encoderSource.set([encoder])
        let encoderStore = makeStore(encoderSource)
        try write("silent", serial: encoder.serial, suffix: "mode")
        try await refresh(encoderStore)
        encoderStore.startMirroring()
        try write("log:[server] ERROR: Capture/encoding error: unsupported resolution", serial: encoder.serial, suffix: "command")
        try await wait("explicit encoder error delivered") { encoderStore.logLines.contains { $0.contains("unsupported resolution") } }
        try write("fail", serial: encoder.serial, suffix: "command")
        try await wait("encoder exit") { !encoderStore.isMirroring }
        try check(encoderStore.sessionState(for: encoder).isFailure && encoderStore.logLines.contains { $0.contains("低负载兼容") } && launches(encoder.serial).count == 1, "a confirmed encoder failure offers explicit compatibility guidance without hidden retries")
        let originalFailure = encoderStore.sessionState(for: encoder)
        let historicalLogs = encoderStore.logLines
        L10n.setLanguage(.english)
        guard case .failed(let englishFailure) = encoderStore.sessionState(for: encoder) else {
            throw CheckFailure(description: "localized device failure disappeared")
        }
        try check(englishFailure.hasPrefix("Mirroring ended after a video capture or encoding error.") && encoderStore.sessionState == .failed(englishFailure) && encoderStore.logLines == historicalLogs && launches(encoder.serial).count == 1 && encoderStore.runningCount == 0, "stored device failures and aggregate failure resolve in English while historical logs and process ownership remain unchanged")
        L10n.setLanguage(.simplifiedChinese)
        try check(encoderStore.sessionState(for: encoder) == originalFailure, "stored device failure restores its original Chinese message")

        let missingTools = MirrorSessionStore(paths: nil, preferences: makePreferences())
        stores.append(missingTools)
        missingTools.startMirroring()
        let missingToolsLogs = missingTools.logLines
        L10n.setLanguage(.english)
        try check(missingTools.globalErrorMessage == "Cannot start: the bundled tools are missing." && missingTools.sessionState == .failed("Cannot start: the bundled tools are missing.") && missingTools.logLines == missingToolsLogs && missingTools.runningCount == 0, "an existing global failure follows language changes without repeating the failed operation")
        L10n.setLanguage(.simplifiedChinese)
        try write("", serial: encoder.serial, suffix: "command")
        encoderStore.clearLogs()
        encoderStore.startMirroring()
        try write("log:ERROR: adb transport encoding failure", serial: encoder.serial, suffix: "command")
        try await wait("generic error delivered") { encoderStore.logLines.contains { $0.contains("adb transport encoding failure") } }
        try write("fail", serial: encoder.serial, suffix: "command")
        try await wait("generic exit") { !encoderStore.isMirroring }
        try check(encoderStore.sessionState(for: encoder).isFailure && !encoderStore.logLines.contains { $0.contains("低负载兼容") }, "generic transport errors do not inherit a previous session's encoder diagnosis")

        // scrcpy may recover encoding at the same resolution without emitting
        // another Texture log. That historical error must not hide a later
        // disconnect. A startup error must also yield to confirmed disconnect
        // evidence, whether conveyed by status 2 or the explicit warning.
        for (suffix, startsReady, disconnectWarning, exitCommand) in [
            ("ACTIVE-STATUS2", true, false, "disconnect"),
            ("ACTIVE-NO-NEW-TEXTURE", true, false, "fail"),
            ("STARTUP-STATUS2", false, false, "disconnect"),
            ("STARTUP-DISCONNECT-WARNING", false, true, "fail")
        ] {
            let target = device("ENCODER-HISTORY-\(suffix)")
            let historySource = SnapshotSource()
            historySource.set([target])
            let historyStore = makeStore(historySource)
            try write(startsReady ? "ready" : "silent", serial: target.serial, suffix: "mode")
            try await refresh(historyStore)
            historyStore.startMirroring()
            if startsReady {
                try await wait("historical encoder test first frame") { historyStore.sessionState(for: target) == .mirroring }
            }
            try write("log:[server] ERROR: Capture/encoding error: transient codec recovery", serial: target.serial, suffix: "command")
            try await wait("historical encoder error delivered") { historyStore.logLines.contains { $0.contains("transient codec recovery") } }
            if disconnectWarning {
                try write("log:WARN: Device disconnected", serial: target.serial, suffix: "command")
                try await wait("disconnect warning delivered") { historyStore.logLines.contains { $0.contains("WARN: Device disconnected") } }
            }
            try write(exitCommand, serial: target.serial, suffix: "command")
            try await wait("disconnect after codec history") { !historyStore.isMirroring }
            guard case .failed(let message) = historyStore.sessionState(for: target) else {
                throw CheckFailure(description: "missing disconnect failure for \(suffix)")
            }
            let textureCount = historyStore.logLines.filter { $0.contains("INFO: Texture:") }.count
            try check(message.contains("请检查 USB") && !message.contains("低负载兼容") && textureCount == (startsReady ? 1 : 0), "\(suffix): historical encoder error cannot override later connection guidance, without a new Texture log")
        }
    }
}

private final class SnapshotSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [AndroidDevice] = []
    private var rawRoutes: [AndroidDevice]?
    private var reads = 0
    private var delay: TimeInterval = 0
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func setDelay(_ delay: TimeInterval) { lock.lock(); self.delay = delay; lock.unlock() }

    func set(_ devices: [AndroidDevice], rawRoutes: [AndroidDevice]? = nil) {
        lock.lock()
        defer { lock.unlock() }
        value = devices
        self.rawRoutes = rawRoutes
    }

    func snapshot() -> ADBSnapshot {
        lock.lock()
        reads += 1
        let result = value
        let routes = rawRoutes
        let pause = delay
        lock.unlock()
        if pause > 0 { Thread.sleep(forTimeInterval: pause) }
        return ADBSnapshot(devices: result, diagnostics: [], rawRoutes: routes)
    }
}

@main
@MainActor
struct MirrorLinkSessionChecks {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: session-checks <mock-scrcpy>")
            exit(2)
        }
        let checks = SessionChecks(executable: URL(fileURLWithPath: CommandLine.arguments[1]))
        do {
            try await checks.run()
            checks.cleanup()
            print("PASS: \(checks.passed) simulated multi-device checks (not real phone/video acceptance)")
        } catch {
            checks.cleanup()
            print("FAIL: \(error)\nFixture evidence: \(checks.root.path)")
            exit(1)
        }
    }
}

@MainActor
private final class SessionChecks {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mirrorlink-session-checks-\(UUID().uuidString)")
    let executable: URL
    var stores: [MirrorSessionStore] = []
    var outsider: Process?
    var preferenceSuites: [String] = []
    var passed = 0

    init(executable: URL) { self.executable = executable }

    var paths: ToolPaths {
        ToolPaths(root: root, adb: URL(fileURLWithPath: "/usr/bin/true"), scrcpy: executable, server: executable)
    }

    func makePreferences() -> UserDefaults {
        let name = "local.mirrorlink.session-checks.\(UUID().uuidString)"
        preferenceSuites.append(name)
        let preferences = UserDefaults(suiteName: name)!
        preferences.removePersistentDomain(forName: name)
        return preferences
    }

    func makeStore(_ source: SnapshotSource, timeout: TimeInterval = 4, preferences: UserDefaults? = nil) -> MirrorSessionStore {
        let store = MirrorSessionStore(paths: paths, startupTimeout: timeout, preferences: preferences ?? makePreferences(), snapshotProvider: { _ in source.snapshot() })
        stores.append(store)
        return store
    }

    func device(_ serial: String, socket: String? = nil, state: DeviceConnectionState = .ready) -> AndroidDevice {
        AndroidDevice(serial: serial, model: "Test_Phone", product: "mock", transport: "USB", state: state, adbSocket: socket)
    }

    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw CheckFailure(description: name) }
        passed += 1
        print("PASS \(passed): \(name)")
    }

    func wait(_ name: String, timeout: TimeInterval = 3, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < deadline else { throw CheckFailure(description: "Timed out: \(name)") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func refresh(_ store: MirrorSessionStore) async throws {
        store.refresh(silent: true)
        try await wait("refresh") { !store.isRefreshing }
    }

    func write(_ text: String, serial: String, suffix: String) throws {
        try text.write(to: root.appendingPathComponent("\(serial).\(suffix)"), atomically: true, encoding: .utf8)
    }

    func launches(_ serial: String) -> [[String: Any]] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("\(serial).launches"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    func cleanup() {
        for store in stores { store.shutdown() }
        if let outsider, outsider.isRunning { outsider.terminate() }
        for name in preferenceSuites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    func run() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = SnapshotSource()
        let store = makeStore(source)
        let a = device("SAMEPREFIX-A")
        let b = device("SAMEPREFIX-B", socket: "tcp:127.0.0.1:5038")
        source.set([a])
        try await refresh(store)
        try check(store.selectedDeviceIDs == [a.id], "single phone selected on first discovery")
        store.clearDeviceSelection()
        try await refresh(store)
        try check(store.selectedDeviceIDs.isEmpty, "periodic refresh respects Clear Selection")
        source.set([a, b])
        try await refresh(store)
        store.selectAllReadyDevices()
        store.startMirroring()
        try check(store.runningCount == 2 && store.sessionState(for: a) == .starting, "two children start independently; no premature video success")
        store.startMirroring()
        try await wait("two frames") { store.sessionState(for: a) == .mirroring && store.sessionState(for: b) == .mirroring }
        try check(launches(a.serial).count == 1 && launches(b.serial).count == 1, "duplicate batch start does not spawn more children")
        let requestA = launches(a.serial)[0]
        let requestB = launches(b.serial)[0]
        try check(requestA["socket"] as? String == "tcp:5037" && requestB["socket"] as? String == b.adbSocket, "each child receives its own ADB socket")
        try check(requestA["androidSerial"] as? String == a.serial && requestB["androidSerial"] as? String == b.serial, "each child receives its own Android serial")
        try check(requestA["adb"] as? String == paths.adb.path && requestB["server"] as? String == paths.server.path, "children use explicit bundled tool paths")
        let argsA = requestA["arguments"] as? [String] ?? []
        let argsB = requestB["arguments"] as? [String] ?? []
        try check(argsA.contains("--window-title=镜连 · Test Phone · SAMEPREFIX-A") && argsB.contains("--window-title=镜连 · Test Phone · SAMEPREFIX-B"), "same-model same-prefix devices get distinct full-serial window titles")

        let reroutedA = device(a.serial, socket: "tcp:127.0.0.1:5038")
        source.set([reroutedA, b])
        try await refresh(store)
        store.startMirroring(for: reroutedA.id)
        try check(store.selectedDeviceIDs.contains(reroutedA.id) && launches(a.serial).count == 1, "daemon route changes preserve identity and prevent duplicate sessions")
        store.clearDeviceSelection()
        source.set([])
        try await refresh(store)
        try check(store.runningCount == 2 && store.displayedDevices.count == 2, "deselection and USB removal retain independent controls")
        store.stopMirroring(for: a.id)
        try await wait("stop only first") { !store.isMirroring(for: a.id) }
        try check(store.isMirroring(for: b.id) && store.sessionState(for: b) == .mirroring, "individual stop leaves other phone running")

        let unauthorized = device("UNAUTHORIZED", state: .unauthorized)
        let offline = device("OFFLINE", state: .offline)
        source.set([a, b, unauthorized, offline])
        try await refresh(store)
        store.selectAllReadyDevices()
        try check(store.selectedDeviceIDs == [a.id, b.id], "Select All excludes unauthorized and offline devices")
        store.setDeviceSelected(unauthorized.id, isSelected: true)
        store.startMirroring()
        try await wait("restart first") { store.sessionState(for: a) == .mirroring }
        try check(launches(unauthorized.serial).isEmpty && !store.canStart(for: offline.id), "mixed selection starts ready phones and skips unavailable phones")

        try write("fail", serial: b.serial, suffix: "command")
        try await wait("independent failure") { store.sessionState(for: b).isFailure && !store.isMirroring(for: b.id) }
        try check(store.sessionState(for: a) == .mirroring && store.sessionSummary.contains("1 台失败"), "failure remains visible while another phone continues mirroring")
        try check(store.canStart(for: b.id), "terminated failed session can be retried")
        try write("", serial: b.serial, suffix: "command")
        store.startMirroring(for: b.id)
        try await wait("retry") { store.sessionState(for: b) == .mirroring }
        try check(launches(b.serial).count == 2, "retry creates exactly one new session")
        try write("exit", serial: a.serial, suffix: "command")
        try await wait("manual window close") { !store.isMirroring(for: a.id) }
        try check(store.sessionState(for: a) == .idle && store.isMirroring(for: b.id), "closing one window returns it to idle without stopping its peer")
        try write("", serial: a.serial, suffix: "command")
        store.startMirroring(for: a.id)
        try await wait("reopen first") { store.sessionState(for: a) == .mirroring }
        store.stopMirroring()
        try await wait("stop all") { !store.isMirroring }
        try check(store.sessionState(for: a) == .idle && store.sessionState(for: b) == .idle, "Stop All reaps all owned children")
        store.setDeviceSelected(a.id, isSelected: true)
        source.set([])
        try await refresh(store)
        source.set([a])
        try await refresh(store)
        try check(store.selectedDeviceIDs.contains(a.id) && !store.isMirroring, "reconnection restores selection but never auto-starts")

        let timeSource = SnapshotSource()
        let timed = device("TIMEOUT")
        timeSource.set([timed])
        try write("silent", serial: timed.serial, suffix: "mode")
        let timeStore = makeStore(timeSource, timeout: 0.25)
        try await refresh(timeStore)
        timeStore.startMirroring()
        try await wait("startup timeout") { timeStore.sessionState(for: timed).isFailure && !timeStore.isMirroring }
        try check(timeStore.logLines.contains { $0.contains("启动超时") }, "missing first frame times out and reaps only that child")
        try write("ready", serial: timed.serial, suffix: "mode")
        timeStore.startMirroring()
        try await wait("timeout retry") { timeStore.sessionState(for: timed) == .mirroring }
        try await Task.sleep(nanoseconds: 2_100_000_000)
        try check(timeStore.isMirroring && timeStore.sessionState(for: timed) == .mirroring, "old delayed termination cannot kill a retried session")

        let stale = device("STALE-TIMER")
        let staleSource = SnapshotSource()
        staleSource.set([stale])
        try write("silent", serial: stale.serial, suffix: "mode")
        let staleStore = makeStore(staleSource, timeout: 0.9)
        try await refresh(staleStore)
        staleStore.startMirroring()
        try await Task.sleep(nanoseconds: 350_000_000)
        staleStore.stopMirroring()
        try await wait("stop before timeout") { !staleStore.isMirroring }
        staleStore.startMirroring()
        try await Task.sleep(nanoseconds: 600_000_000)
        try check(staleStore.sessionState(for: stale) == .starting, "old startup timeout cannot fail a new starting session")
        try write("ready", serial: stale.serial, suffix: "command")
        try await wait("new frame") { staleStore.sessionState(for: stale) == .mirroring }

        let failure = device("FAST-FAILURE")
        let failSource = SnapshotSource()
        failSource.set([failure])
        try write("fail", serial: failure.serial, suffix: "mode")
        let failStore = makeStore(failSource)
        try await refresh(failStore)
        failStore.startMirroring()
        try await wait("fast child failure") { failStore.sessionState(for: failure).isFailure && !failStore.isMirroring }
        try check(failStore.logLines.contains { $0.contains("模拟错误：授权失败") } && failStore.logLines.contains { $0.contains("最后一条无换行诊断") }, "fast-exit logs drain completely including split UTF-8 and unterminated final line")

        let buffered = device("BUFFERED-STDIO")
        let bufferedSource = SnapshotSource()
        bufferedSource.set([buffered])
        let bufferedStore = makeStore(bufferedSource, timeout: 0.5)
        try await refresh(bufferedStore)
        bufferedStore.startMirroring()
        try await wait("C stdio readiness", timeout: 0.45) { bufferedStore.sessionState(for: buffered) == .mirroring }
        try await Task.sleep(nanoseconds: 650_000_000)
        try check(bufferedStore.sessionState(for: buffered) == .mirroring, "buffered C stdout is received live and survives the startup watchdog")
        bufferedStore.stopMirroring()
        try await wait("PTY EOF") { !bufferedStore.isMirroring }
        try check(bufferedStore.sessionState(for: buffered) == .idle, "PTY hangup is handled as EOF without crashing the parent")

        let inherited = device("INHERITED-LOGS")
        let inheritedSource = SnapshotSource()
        inheritedSource.set([inherited])
        try write("inherited-logs", serial: inherited.serial, suffix: "mode")
        let inheritedStore = makeStore(inheritedSource)
        try await refresh(inheritedStore)
        inheritedStore.startMirroring()
        try await wait("bounded inherited log drain", timeout: 1.5) { !inheritedStore.isMirroring }
        try check(inheritedStore.sessionState(for: inherited).isFailure && inheritedStore.canStart, "child exit cannot leave an unretryable session when descendants retain logs")
        try check(inheritedStore.logLines.contains { $0.contains("final buffered stdout") } && inheritedStore.logLines.contains { $0.contains("final stderr") }, "bounded exit drain preserves final stdout and stderr")
        try write("ready", serial: inherited.serial, suffix: "mode")
        inheritedStore.startMirroring()
        try await wait("retry before old descendant exits") { inheritedStore.sessionState(for: inherited) == .mirroring }
        try check(inheritedStore.runningCount == 1, "retry uses fresh log channels while old inherited descriptors finish")

        let stubborn = device("IGNORE-TERM")
        let healthy = device("HEALTHY")
        let stopSource = SnapshotSource()
        stopSource.set([stubborn, healthy])
        try write("ignore-term", serial: stubborn.serial, suffix: "mode")
        let stopStore = makeStore(stopSource)
        try await refresh(stopStore)
        stopStore.selectAllReadyDevices()
        stopStore.startMirroring()
        try await wait("stubborn process ready") { stopStore.sessionState(for: stubborn) == .mirroring && stopStore.sessionState(for: healthy) == .mirroring }
        stopStore.stopMirroring(for: stubborn.id)
        try await wait("targeted force-stop", timeout: 4) { !stopStore.isMirroring(for: stubborn.id) }
        try check(stopStore.isMirroring(for: healthy.id), "unresponsive child is force-stopped without affecting another phone")

        let external = Process()
        external.executableURL = executable
        external.arguments = ["-s", "UNRELATED"]
        external.currentDirectoryURL = root
        external.standardOutput = FileHandle.nullDevice
        external.standardError = FileHandle.nullDevice
        try external.run()
        outsider = external
        stopStore.startMirroring(for: stubborn.id)
        try await wait("shutdown children ready") { stopStore.sessionState(for: stubborn) == .mirroring }
        stopStore.shutdown()
        try await wait("shutdown reaps owned children") { !stopStore.isMirroring }
        try check(external.isRunning, "Quit terminates owned sessions but preserves unrelated process")
        stopStore.startMirroring(for: healthy.id)
        try check(!stopStore.isMirroring, "shutdown store cannot restart a session")

        let badExecutable = root.appendingPathComponent("invalid-executable")
        try "not an executable".write(to: badExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: badExecutable.path)
        let badPaths = ToolPaths(root: root, adb: paths.adb, scrcpy: badExecutable, server: executable)
        let badStore = MirrorSessionStore(paths: badPaths, preferences: makePreferences(), snapshotProvider: { _ in ADBSnapshot(devices: [a], diagnostics: []) })
        stores.append(badStore)
        try await refresh(badStore)
        badStore.startMirroring()
        try check(badStore.sessionState(for: a).isFailure && !badStore.isMirroring && badStore.canStart, "Process.run failure leaves no phantom active session")

        let mixedSource = SnapshotSource()
        let mixedStore = makeStore(mixedSource)
        let wired = device("WIRELESS-HARDWARE")
        var wifi = AndroidDevice(serial: "192.168.1.8:39847", model: "Test_Phone", product: "mock", transport: "Wi-Fi", state: .ready, adbSocket: nil)
        wifi.hardwareSerial = wired.serial
        mixedSource.set([wired])
        try await refresh(mixedStore)
        mixedStore.startMirroring()
        try await wait("wired frame") { mixedStore.sessionState(for: wired) == .mirroring }
        mixedSource.set([wifi])
        mixedStore.connectAndMirror(wifi)
        try await refresh(mixedStore)
        try check(mixedStore.runningCount == 1 && launches(wifi.serial).isEmpty, "USB plus Wi-Fi same hardware never launches duplicate session")
        try check(mixedStore.displayedDevices.first?.transport == "USB", "existing process stays visibly pinned to its USB route")
        mixedStore.stopMirroring(for: wifi.id)
        try await wait("stop old route") { !mixedStore.isMirroring }
        mixedStore.connectAndMirror(wifi)
        try await wait("Wi-Fi frame") { mixedStore.sessionState(for: wifi) == .mirroring }
        try check(launches(wifi.serial).count == 1 && mixedStore.displayedDevices.first?.isWireless == true, "stop/restart switches to verified Wi-Fi transport")
        let wiredPeer = device("WIRED-PEER", socket: "tcp:127.0.0.1:5038")
        mixedSource.set([wifi, wiredPeer])
        try await refresh(mixedStore)
        mixedStore.startMirroring(for: wiredPeer.id)
        try await wait("mixed transports") { mixedStore.sessionState(for: wiredPeer) == .mirroring }
        try check(mixedStore.runningCount == 2, "USB and wireless phones mirror independently")
        try write("fail", serial: wifi.serial, suffix: "command")
        try await wait("Wi-Fi lost") { mixedStore.sessionState(for: wifi).isFailure }
        try check(mixedStore.isMirroring(for: wiredPeer.id) && mixedStore.logLines.contains { $0.contains("端口变化") }, "wireless loss gives reconnect guidance without stopping USB peer")

        let identitySource = SnapshotSource()
        let identityStore = makeStore(identitySource)
        var lateIdentity = AndroidDevice(serial: "192.168.1.10:39848", model: "Test_Phone", product: "mock", transport: "Wi-Fi", state: .ready, adbSocket: nil)
        identitySource.set([lateIdentity])
        try await refresh(identityStore)
        identityStore.startMirroring()
        let originalID = lateIdentity.id
        try await wait("unresolved Wi-Fi identity starts") { identityStore.sessionStates[originalID] == .mirroring }
        lateIdentity.hardwareSerial = "LATE-HARDWARE"
        identitySource.set([lateIdentity, device("LATE-HARDWARE")])
        try await refresh(identityStore)
        identityStore.connectAndMirror(lateIdentity)
        try check(identityStore.devices.count == 1 && identityStore.devices[0].id == originalID && identityStore.runningCount == 1 && launches(lateIdentity.serial).count == 1, "late hardware identity preserves selection and running process key")
        var unavailableIdentity = lateIdentity
        unavailableIdentity.hardwareSerial = nil
        identitySource.set([unavailableIdentity])
        try await refresh(identityStore)
        try check(identityStore.devices[0].id == originalID && identityStore.devices[0].hardwareSerial == "LATE-HARDWARE" && identityStore.selectedDeviceIDs.contains(originalID), "transient getprop failure does not lose learned hardware identity")
        identitySource.set([])
        try await refresh(identityStore)
        identitySource.set([device("LATE-HARDWARE")])
        try await refresh(identityStore)
        try check(identityStore.devices[0].id == originalID && !identityStore.canStart(for: originalID), "USB rediscovery after Wi-Fi loss retains live session ownership")
        try await runQualityChecks()
        try await runProductivityChecks()
        try await runWindowControlChecks()
    }
}

@MainActor
private extension SessionChecks {
    func runWindowControlChecks() async throws {
        let channel = try MirrorWindowChannel()
        let payload: [String: Any] = ["type": "state", "status": String(repeating: "测试", count: 1000)]
        channel.sendState(payload)
        var buffer = [UInt8](repeating: 0, count: 8192)
        let received = recv(channel.input.fileDescriptor, &buffer, buffer.count, MSG_DONTWAIT)
        try check(received > 6000, "large bilingual state and media paths exceed Darwin defaults without losing toolbar state")
        channel.close()
        let source = SnapshotSource()
        let a = device("WINDOW-A", socket: "tcp:127.0.0.1:5038")
        let b = device("WINDOW-B")
        source.set([a, b])
        let store = makeStore(source)
        var events: [(MirrorWindowAction, AndroidDevice)] = []
        var files: [(MirrorWindowAction, URL, AndroidDevice)] = []
        var busy = false
        store.windowToolState = { _ in ["busy": busy, "resultID": "initial"] }
        store.onWindowToolAction = { events.append(($0, $1)) }
        store.onWindowFileAction = { files.append(($0, $1, $2)) }
        var mainWindowRequests = 0
        store.onShowMainWindow = { mainWindowRequests += 1 }
        try await refresh(store)
        store.selectAllReadyDevices()
        store.startMirroring()
        try await wait("window controls ready") { store.runningCount == 2 && store.sessionState(for: a) == .mirroring && store.sessionState(for: b) == .mirroring }
        try write("window:{\"action\":\"showMain\"}", serial: a.serial, suffix: "command")
        try await wait("restore main from mirror") { mainWindowRequests == 1 }
        try check(store.runningCount == 2 && launches(a.serial).count == 1 && launches(b.serial).count == 1,
                  "opening device manager from a mirror preserves both active sessions")
        try write("window:{\"action\":\"home\"}", serial: a.serial, suffix: "command")
        try await wait("home from first window") { events.count == 1 }
        try check(events[0].0 == .home && events[0].1 == a, "window action preserves exact first device and ADB route")
        try write("window:{\"action\":\"drawer\"}", serial: b.serial, suffix: "command")
        try await wait("drawer from second window") { events.count == 2 }
        try check(events[1].0 == .drawer && events[1].1 == b, "second private window channel cannot target first phone")
        for invalid in ["{", "{\"action\":\"shell\"}", "{\"action\":\"screenshot\",\"path\":42}", String(repeating: "x", count: 9000)] {
            try write("window:" + invalid, serial: a.serial, suffix: "command")
            try await Task.sleep(nanoseconds: 90_000_000)
        }
        try check(events.count == 2, "malformed unknown and oversized window requests are rejected")
        busy = true
        try write("window:{\"action\":\"screenshot\"}", serial: a.serial, suffix: "command")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(events.count == 2, "parent independently blocks capture while device tool is busy")
        busy = false
        var options = store.preferences(for: a)
        options.presentationMode = true
        store.updatePreferences(for: a, preferences: options)
        try write("window:{\"action\":\"swipe\"}", serial: a.serial, suffix: "command")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(events.count == 2, "presentation mode rejects navigation in the parent")
        try write("window:{\"action\":\"screenshot\"}", serial: a.serial, suffix: "command")
        try await wait("capture still allowed") { events.count == 3 }
        try check(events.last?.0 == .screenshot, "presentation mode retains screenshot availability")
        try write("window:{\"action\":\"sendFile\",\"path\":\"/tmp/example.txt\"}", serial: a.serial, suffix: "command")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(files.isEmpty, "presentation mode blocks file writes independently of child UI")
        for invalid in ["{\"action\":\"sendFile\",\"path\":\"/tmp/app.apk\"}", "{\"action\":\"installAPK\",\"path\":\"/tmp/file.txt\"}", "{\"action\":\"installAPK\",\"path\":\"relative.apk\"}"] {
            try write("window:" + invalid, serial: b.serial, suffix: "command")
            try await Task.sleep(nanoseconds: 90_000_000)
        }
        try check(files.isEmpty, "APK installation requires the separate install action and an absolute APK path")
        try write("window:{\"action\":\"sendFile\",\"path\":\"/tmp/example.txt\"}", serial: b.serial, suffix: "command")
        try await wait("file route") { files.count == 1 }
        try check(files[0].0 == .sendFile && files[0].2 == b, "file picker request stays bound to its own phone")
        try write("window:{\"action\":\"installAPK\",\"path\":\"/tmp/example.apk\"}", serial: b.serial, suffix: "command")
        try await wait("apk route") { files.count == 2 }
        try check(files[1].0 == .installAPK && files[1].2 == b, "confirmed APK request stays bound to its own phone")
        try write("window:{\"action\":\"recordStart\",\"path\":\"relative.mp4\"}", serial: b.serial, suffix: "command")
        try await Task.sleep(nanoseconds: 100_000_000)
        try check(!store.isRecording(for: b.id) && launches(b.serial).count == 1, "relative recording destinations cannot restart a session")
        let peerPID = launches(b.serial).last?["pid"] as? Int
        store.stopMirroring(for: a.id)
        try await wait("first toolbar closes") { !store.isMirroring(for: a.id) }
        try write("window:{\"action\":\"home\"}", serial: b.serial, suffix: "command")
        try await wait("peer toolbar survives") { events.count == 4 }
        try check(launches(b.serial).last?["pid"] as? Int == peerPID && events.last?.1 == b, "closing one window preserves peer process and action channel")
        store.stopMirroring()
        try await wait("toolbar sessions stopped") { !store.isMirroring }
    }

    func recoveryStore(_ source: SnapshotSource, preferences: UserDefaults? = nil) -> MirrorSessionStore {
        let store = MirrorSessionStore(paths: paths, startupTimeout: 0.8, preferences: preferences ?? makePreferences(),
            reconnectDelays: [0.12, 0.16, 0.2], layoutBounds: { CGRect(x: 0, y: 25, width: 1440, height: 850) },
            snapshotProvider: { _ in source.snapshot() })
        stores.append(store)
        return store
    }

    func runProductivityChecks() async throws {
        let source = SnapshotSource()
        let a = device("PRODUCTIVITY-A")
        let b = device("PRODUCTIVITY-B", socket: "tcp:127.0.0.1:5038")
        source.set([a, b])
        let prefs = makePreferences()
        let store = recoveryStore(source, preferences: prefs)
        try await refresh(store)
        var settings = DevicePreferences()
        settings.nickname = "  演示\n手机  "
        settings.favorite = true
        settings.qualityProfile = .compatibility
        settings.audioEnabled = false
        settings.presentationMode = true
        settings.alwaysOnTop = true
        store.updatePreferences(for: a, preferences: settings)
        store.setDeviceSelected(a.id, isSelected: true)
        store.windowLayout = .grid
        let restored = recoveryStore(source, preferences: prefs)
        try await refresh(restored)
        try check(restored.displayName(for: a) == "演示手机" && restored.preferences(for: a).favorite && restored.preferences(for: a).qualityProfile == .compatibility && restored.displaySerial(for: a) == nil, "device nickname, favorite, presentation and quality survive a new store")
        try check(restored.selectedDeviceIDs == [a.id] && !restored.isMirroring && restored.windowLayout == .grid, "saved selection and layout restore without automatically starting a phone")
        var wifi = AndroidDevice(serial: "192.0.2.17:41111", model: "Changed_Model", product: nil, transport: "Wi-Fi", state: .ready, adbSocket: nil)
        wifi.hardwareSerial = a.serial
        try check(restored.preferences(for: wifi).nickname == "演示手机", "verified hardware identity shares preferences across USB and changed wireless routes")
        var unidentified = wifi
        unidentified.hardwareSerial = nil
        var unsafeSettings = settings
        unsafeSettings.autoReconnect = true
        restored.updatePreferences(for: unidentified, preferences: unsafeSettings)
        try check(!restored.preferences(for: unidentified).autoReconnect && !restored.preferences(for: unidentified).favorite && !restored.knownDevices.contains { $0.id.contains("192.0.2") }, "an unverified wireless endpoint cannot persist IP-based favorites or automatic recovery")
        let clean = recoveryStore(source, preferences: prefs)
        try check(clean.preferences(for: unidentified).nickname.isEmpty, "unverified wireless options are session-only")
        restored.clearDeviceSelection()
        let cleared = recoveryStore(source, preferences: prefs)
        try await refresh(cleared)
        try check(cleared.selectedDeviceIDs.isEmpty, "an explicitly empty saved selection is not replaced by discovery")
        restored.forgetKnownDevice(DevicePreferences.identity(for: a)!)
        try check(restored.preferences(for: a).nickname.isEmpty && restored.knownDevices.allSatisfy { $0.id != DevicePreferences.identity(for: a) }, "forgetting a device resets this app's saved preferences")

        store.selectAllReadyDevices()
        store.startMirroring()
        try await wait("per-device preferences") { store.sessionState(for: a) == .mirroring && store.sessionState(for: b) == .mirroring }
        let argsA = launches(a.serial).last?["arguments"] as? [String] ?? []
        let argsB = launches(b.serial).last?["arguments"] as? [String] ?? []
        try check(argsA.contains("--window-title=镜连 · 演示手机") && !argsA.contains(where: { $0.hasPrefix("--window-title=") && $0.contains(a.serial) }) && argsA.contains("--no-control") && argsA.contains("--no-clipboard-autosync") && argsA.contains("--no-audio"), "presentation removes serial from the title and applies read-only, clipboard and audio isolation")
        try check(argsA.contains("--max-size=1920") && argsB.contains("--max-size=0") && !argsB.contains("--no-audio") && !argsB.contains("--no-control") && !argsB.contains(where: { $0.hasPrefix("--audio-codec=") }), "per-device overrides do not change a peer's quality, audio or control, and ordinary mirroring keeps its default audio codec")
        try check(argsA.first { $0.hasPrefix("--window-x=") } != argsB.first { $0.hasPrefix("--window-x=") }, "batch layout assigns separate initial window cells")
        let peerPID = launches(b.serial).last?["pid"] as? Int
        let originalPID = launches(a.serial).last?["pid"] as? Int
        settings.fullscreen = true
        store.updatePreferences(for: a, preferences: settings)
        try check(launches(a.serial).last?["pid"] as? Int == originalPID, "editing device preferences does not silently restart an active session")
        var toggled = settings; toggled.presentationMode = false
        store.updatePreferences(for: a, preferences: toggled)
        try check(store.isPresentationMode(for: a) && store.isReadOnlySession(for: a.id) && store.displaySerial(for: a) == nil, "turning off a next-session preference cannot bypass an active read-only presentation")
        store.updatePreferences(for: a, preferences: settings)
        store.restartMirroring(for: a.id)
        try await wait("apply fullscreen") { launches(a.serial).count == 2 && store.sessionState(for: a) == .mirroring }
        let fullscreenArgs = launches(a.serial).last?["arguments"] as? [String] ?? []
        try check(fullscreenArgs.contains("--fullscreen") && !fullscreenArgs.contains(where: { $0.hasPrefix("--window-x=") }) && launches(b.serial).last?["pid"] as? Int == peerPID, "explicit restart applies fullscreen without conflicting placement or restarting a peer")

        let movie = root.appendingPathComponent("演示 movie.mp4")
        store.startRecording(for: a.id, to: movie)
        store.startRecording(for: a.id, to: root.appendingPathComponent("duplicate.mp4"))
        try await wait("recording restarted") { launches(a.serial).count == 3 && store.sessionState(for: a) == .mirroring }
        let silentRecordArguments = launches(a.serial).last?["arguments"] as? [String] ?? []
        try check(store.isRecording(for: a.id) && store.recordingURL(for: a.id) == movie && !FileManager.default.fileExists(atPath: movie.path) && silentRecordArguments.contains("--no-audio") && !silentRecordArguments.contains(where: { $0.hasPrefix("--audio-codec=") }), "silent recording reserves a private temporary output, rejects duplicate requests and never initializes an audio encoder")
        store.stopRecording(for: a.id)
        try await wait("recording finalized and mirror resumes") { launches(a.serial).count == 4 && store.sessionState(for: a) == .mirroring }
        try check(store.lastRecordingURL(for: a.id) == movie && FileManager.default.fileExists(atPath: movie.path) && !store.isRecording(for: a.id), "graceful recording stop publishes a finalized MP4 and resumes only its mirror")
        try check(launches(b.serial).last?["pid"] as? Int == peerPID && !(launches(a.serial).last?["arguments"] as? [String] ?? []).contains(where: { $0.hasPrefix("--record=") }), "record-stop preserves its peer and the replacement session has no recording flag")
        let existing = try Data(contentsOf: movie)
        store.startRecording(for: a.id, to: movie)
        let afterExisting = try Data(contentsOf: movie)
        try check(afterExisting == existing && launches(a.serial).count == 4 && !store.isRecording(for: a.id), "choosing an existing file cannot overwrite it or restart the session")

        for mode in ["record-incomplete", "record-bad-container", "record-final-no-newline", "record-failed"] {
            let device = device("RECORD-\(mode)")
            let source = SnapshotSource()
            source.set([device])
            let store = recoveryStore(source)
            try write(mode, serial: device.serial, suffix: "mode")
            try await refresh(store)
            let target = root.appendingPathComponent("\(mode).mp4")
            store.startRecording(for: device.id, to: target)
            try await wait("recording mode \(mode)") { store.sessionState(for: device) == .mirroring }
            store.stopMirroring(for: device.id)
            try await wait("finalize \(mode)") { !store.isMirroring }
            if mode == "record-final-no-newline" {
                try check(store.lastRecordingURL(for: device.id) == target, "an unterminated final completion log is drained before deciding recording success")
            } else {
                try check(store.lastRecordingURL(for: device.id) == nil && !FileManager.default.fileExists(atPath: target.path) && store.recordingMessage(for: device.id)?.contains("未完整") == true, "\(mode) cannot publish or claim a completed recording")
            }
        }

        let race = device("RECORD-PUBLISH-RACE")
        let raceSource = SnapshotSource(); raceSource.set([race])
        let raceStore = recoveryStore(raceSource)
        try await refresh(raceStore)
        let raceURL = root.appendingPathComponent("racing-destination.mp4")
        raceStore.startRecording(for: race.id, to: raceURL)
        try await wait("race recording ready") { raceStore.sessionState(for: race) == .mirroring }
        try Data("other user's file".utf8).write(to: raceURL)
        raceStore.stopMirroring()
        try await wait("race recording stops") { !raceStore.isMirroring }
        let afterRace = try String(contentsOf: raceURL, encoding: .utf8)
        try check(afterRace == "other user's file" && raceStore.lastRecordingURL(for: race.id) == nil, "a destination created during recording is never overwritten at finalization")

        let quit = device("RECORD-QUIT")
        let quitSource = SnapshotSource(); quitSource.set([quit])
        let quitStore = recoveryStore(quitSource)
        try await refresh(quitStore)
        let quitURL = root.appendingPathComponent("quit.mp4")
        quitStore.startRecording(for: quit.id, to: quitURL)
        try await wait("quit recording ready") { quitStore.sessionState(for: quit) == .mirroring }
        let audibleRecordArguments = launches(quit.serial).last?["arguments"] as? [String] ?? []
        try check(audibleRecordArguments.contains("--audio-codec=aac") && audibleRecordArguments.contains("--record-format=mp4") && !audibleRecordArguments.contains("--no-audio"), "recording with audio starts the child with AAC in an MP4 container")
        quitStore.shutdown()
        try check(FileManager.default.fileExists(atPath: quitURL.path) && quitStore.lastRecordingURL(for: quit.id) == quitURL, "synchronous Quit drains recording evidence and finalizes the file before returning")

        let recovery = device("AUTO-RECOVER")
        let recoverySource = SnapshotSource(); recoverySource.set([recovery])
        let recoveryStore = recoveryStore(recoverySource)
        try await refresh(recoveryStore)
        var recoveryOptions = DevicePreferences(); recoveryOptions.autoReconnect = true
        recoveryStore.updatePreferences(for: recovery, preferences: recoveryOptions)
        recoveryStore.startMirroring()
        try await wait("recovery origin ready") { recoveryStore.sessionState(for: recovery) == .mirroring }
        try await Task.sleep(nanoseconds: 180_000_000)
        try check(launches(recovery.serial).count == 1 && !recoveryStore.hasPendingReconnect, "a quiet static session never triggers automatic recovery")
        try write("disconnect", serial: recovery.serial, suffix: "command")
        try await wait("pending recovery") { recoveryStore.hasPendingReconnect }
        try write("", serial: recovery.serial, suffix: "command")
        try await wait("recovery frame") { launches(recovery.serial).count == 2 && recoveryStore.sessionState(for: recovery) == .mirroring }
        try check(!recoveryStore.hasPendingReconnect && recoveryStore.runningCount == 1, "a confirmed disconnect recovers exactly the authorized hardware without duplicate sessions")
        try write("disconnect", serial: recovery.serial, suffix: "command")
        try await wait("bounded repeated disconnects", timeout: 3) { launches(recovery.serial).count == 4 && !recoveryStore.isMirroring && !recoveryStore.hasPendingReconnect }
        try check(recoveryStore.logLines.contains { $0.contains("已尝试恢复连接 3 次") }, "automatic recovery is bounded to three launches across repeated immediate disconnections")
        try write("", serial: recovery.serial, suffix: "command")
        recoveryStore.startMirroring()
        try await wait("manual reset retry budget") { recoveryStore.sessionState(for: recovery) == .mirroring }
        try write("disconnect", serial: recovery.serial, suffix: "command")
        try await wait("recovery pending for cancellation") { recoveryStore.hasPendingReconnect }
        recoveryStore.cancelReconnect(for: recovery.id)
        let count = launches(recovery.serial).count
        try await Task.sleep(nanoseconds: 550_000_000)
        try check(!recoveryStore.hasPendingReconnect && launches(recovery.serial).count == count, "cancel invalidates a delayed recovery callback")
        try write("", serial: recovery.serial, suffix: "command")
        recoveryStore.startMirroring()
        try await wait("manual window-close fixture") { recoveryStore.sessionState(for: recovery) == .mirroring }
        try write("log:WARN: Device disconnected", serial: recovery.serial, suffix: "command")
        try await wait("historical disconnect warning before manual close") { recoveryStore.logLines.contains { $0.contains("WARN: Device disconnected") } }
        try write("exit", serial: recovery.serial, suffix: "command")
        try await wait("manual window closed") { !recoveryStore.isMirroring }
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(!recoveryStore.hasPendingReconnect && recoveryStore.sessionState(for: recovery) == .idle, "a normal window close overrides historical disconnect warnings and never triggers recovery")

        try write("", serial: recovery.serial, suffix: "command")
        recoveryStore.startMirroring()
        try await wait("generic failure origin") { recoveryStore.sessionState(for: recovery) == .mirroring }
        try write("fail", serial: recovery.serial, suffix: "command")
        try await wait("generic failure exit") { !recoveryStore.isMirroring }
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(!recoveryStore.hasPendingReconnect && recoveryStore.sessionState(for: recovery).isFailure, "a generic component failure without disconnect evidence is not silently retried")

        let stale = device("RECOVERY-INFLIGHT")
        let staleSource = SnapshotSource(); staleSource.set([stale])
        let staleStore = self.recoveryStore(staleSource)
        try await refresh(staleStore)
        staleStore.updatePreferences(for: stale, preferences: recoveryOptions)
        staleStore.startMirroring()
        try await wait("inflight recovery origin") { staleStore.sessionState(for: stale) == .mirroring }
        staleSource.setDelay(0.25)
        let initialReads = staleSource.readCount
        try write("disconnect", serial: stale.serial, suffix: "command")
        try await wait("recovery discovery is in flight") { staleSource.readCount > initialReads }
        staleStore.cancelReconnect(for: stale.id)
        try write("", serial: stale.serial, suffix: "command")
        try await Task.sleep(nanoseconds: 400_000_000)
        try check(launches(stale.serial).count == 1 && !staleStore.hasPendingReconnect && !staleStore.isMirroring, "a late discovery response after cancellation cannot launch a replacement session")

        var wifiTarget = AndroidDevice(serial: "192.0.2.77:42222", model: "Mock", product: nil, transport: "Wi-Fi", state: .ready, adbSocket: nil)
        wifiTarget.hardwareSerial = "EXPECTED-HARDWARE"
        let wifiSource = SnapshotSource(); wifiSource.set([wifiTarget])
        let wifiStore = self.recoveryStore(wifiSource)
        try await refresh(wifiStore)
        wifiStore.updatePreferences(for: wifiTarget, preferences: recoveryOptions)
        wifiStore.startMirroring()
        try await wait("wireless identity origin") { wifiStore.sessionState(for: wifiTarget) == .mirroring }
        var impostor = wifiTarget; impostor.hardwareSerial = "OTHER-HARDWARE"
        wifiSource.set([impostor])
        try write("disconnect", serial: wifiTarget.serial, suffix: "command")
        try await wait("wireless recovery pending") { wifiStore.hasPendingReconnect }
        try await wait("wireless identity rejection") { !wifiStore.hasPendingReconnect }
        try check(launches(wifiTarget.serial).count == 1 && !wifiStore.isMirroring, "a different phone reusing the same IP and port is never accepted by recovery")

        let missing = device("AUTO-MISSING")
        let missingSource = SnapshotSource(); missingSource.set([missing])
        let missingStore = self.recoveryStore(missingSource)
        try await refresh(missingStore)
        missingStore.updatePreferences(for: missing, preferences: recoveryOptions)
        missingStore.startMirroring()
        try await wait("missing origin ready") { missingStore.sessionState(for: missing) == .mirroring }
        let reads = missingSource.readCount
        missingSource.set([device("DIFFERENT-PHONE")])
        try write("disconnect", serial: missing.serial, suffix: "command")
        try await wait("missing waits") { missingStore.hasPendingReconnect }
        try await wait("missing retries exhausted") { !missingStore.hasPendingReconnect }
        try check(missingSource.readCount - reads == 3 && launches("DIFFERENT-PHONE").isEmpty && launches(missing.serial).count == 1, "three bounded discovery retries never substitute a different connected phone")
        missingSource.set([missing])
        try write("", serial: missing.serial, suffix: "command")
        try await refresh(missingStore)
        missingStore.startMirroring()
        try await wait("stop-all recovery origin") { missingStore.sessionState(for: missing) == .mirroring }
        try write("disconnect", serial: missing.serial, suffix: "command")
        try await wait("stop-all recovery queued") { missingStore.hasPendingReconnect }
        missingStore.stopMirroring()
        let beforeStopAll = launches(missing.serial).count
        try await Task.sleep(nanoseconds: 550_000_000)
        try check(!missingStore.hasPendingReconnect && launches(missing.serial).count == beforeStopAll, "Stop All cancels recovery even when no child is currently alive")

        let routedUSB = device("RECOVERY-RAW-ROUTES")
        var routedWiFi = AndroidDevice(serial: "192.0.2.99:43333", model: "Mock", product: nil, transport: "Wi-Fi", state: .ready, adbSocket: nil)
        routedWiFi.hardwareSerial = routedUSB.serial
        let otherDaemon = device(routedUSB.serial, socket: "tcp:127.0.0.1:5038")
        let routeSource = SnapshotSource(); routeSource.set([routedUSB])
        let routeStore = self.recoveryStore(routeSource)
        try await refresh(routeStore)
        routeStore.updatePreferences(for: routedUSB, preferences: recoveryOptions)
        routeStore.startMirroring()
        try await wait("raw route origin") { routeStore.sessionState(for: routedUSB) == .mirroring }
        // The UI chooses the same phone's Wi-Fi row, while both USB daemons
        // remain discoverable. Recovery must use the exact original USB route.
        routeSource.set([routedWiFi], rawRoutes: [routedWiFi, otherDaemon, routedUSB])
        try await refresh(routeStore)
        routeSource.setDelay(0.18)
        let routeReads = routeSource.readCount
        try write("disconnect", serial: routedUSB.serial, suffix: "command")
        try await wait("raw route discovery in flight") { routeSource.readCount > routeReads }
        var latestOptions = recoveryOptions
        latestOptions.nickname = "最新演示设置"
        latestOptions.presentationMode = true
        latestOptions.audioEnabled = false
        latestOptions.qualityProfile = .compatibility
        routeStore.updatePreferences(forKnownDeviceID: DevicePreferences.identity(for: routedUSB)!, preferences: latestOptions)
        try write("", serial: routedUSB.serial, suffix: "command")
        try await wait("original raw route recovered") { launches(routedUSB.serial).count == 2 && routeStore.sessionState(for: routedUSB) == .mirroring }
        let recoveredRequest = launches(routedUSB.serial).last!
        let recoveredArguments = recoveredRequest["arguments"] as? [String] ?? []
        try check(recoveredRequest["socket"] as? String == "tcp:5037" && launches(routedWiFi.serial).isEmpty && routeStore.runningCount == 1, "UI route deduplication cannot hide the original USB route or switch recovery to Wi-Fi or another daemon")
        try check(recoveredArguments.contains("--no-control") && recoveredArguments.contains("--no-clipboard-autosync") && recoveredArguments.contains("--no-audio") && recoveredArguments.contains("--max-size=1920") && recoveredArguments.contains("--window-title=镜连 · 最新演示设置"), "a recovered process adopts preferences saved while discovery was in flight, including read-only, sound and quality")
        try check(routeStore.activePreferences(for: routedUSB.id)?.presentationMode == true && routeStore.displaySerial(for: routedUSB) == nil, "recovered-session snapshot agrees with the newly applied presentation restrictions")
        routeStore.stopMirroring()
        try await wait("raw route fixture stopped") { !routeStore.isMirroring }
        store.stopMirroring()
        try await wait("productivity peers stopped") { !store.isMirroring }
    }
}
