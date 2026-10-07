import Combine
import Foundation
import Darwin

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
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
    var passed = 0

    init(executable: URL) { self.executable = executable }

    var paths: ToolPaths {
        ToolPaths(root: root, adb: URL(fileURLWithPath: "/usr/bin/true"), scrcpy: executable, server: executable)
    }

    func makeStore(_ source: SnapshotSource, timeout: TimeInterval = 4) -> MirrorSessionStore {
        let store = MirrorSessionStore(paths: paths, startupTimeout: timeout, snapshotProvider: { _ in source.snapshot() })
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
        let badStore = MirrorSessionStore(paths: badPaths, snapshotProvider: { _ in ADBSnapshot(devices: [a], diagnostics: []) })
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
    }
}
