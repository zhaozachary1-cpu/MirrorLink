import Combine
import Foundation
import Darwin

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private extension SessionChecks {
    func runQualityChecks() async throws {
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
        try await refresh(store)
        store.selectAllReadyDevices()
        store.startMirroring()
        try await wait("quality frames") { store.sessionState(for: a) == .mirroring && store.sessionState(for: b) == .mirroring }
        try check(store.videoStatus(for: a.id)?.profile == .nativeClarity && store.videoStatus(for: a.id)?.resolution?.pixelCount == 2_592_000, "a session reports its actual first-frame dimensions and starting profile")
        let peerPID = launches(b.serial).last?["pid"] as? Int
        store.qualityProfile = .nativeSmooth
        try check(store.videoStatus(for: a.id)?.profile == .nativeClarity && store.videoStatus(for: b.id)?.profile == .nativeClarity && launches(a.serial).count == 1 && launches(b.serial).count == 1, "changing global quality neither relabels nor restarts active sessions")

        try write("log:INFO: Texture: 2400x1080", serial: a.serial, suffix: "command")
        try await wait("orientation update") { store.logLines.contains { $0.contains("Texture: 2400x1080") } }
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

    func set(_ devices: [AndroidDevice]) {
        lock.lock()
        defer { lock.unlock() }
        value = devices
    }

    func snapshot() -> ADBSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ADBSnapshot(devices: value, diagnostics: [])
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
    }
}
