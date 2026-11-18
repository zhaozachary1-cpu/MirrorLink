import Foundation
import CoreGraphics
import ImageIO
import Darwin

private final class CompletedToolWorkers: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return completed }
    func finish() { lock.lock(); completed += 1; lock.unlock() }
}

private final class MockADB: @unchecked Sendable {
    struct Call { let arguments: [String]; let environment: [String: String] }
    private let lock = NSLock()
    private var recorded: [Call] = []
    var mode = "normal"
    var png = Data()
    var stagedBytes: Data?
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }
    func clear() { lock.lock(); recorded = []; lock.unlock() }
    func run(_ args: [String], _ environment: [String: String], _ timeout: TimeInterval, _ limit: Int,
             _ cancellation: ProcessCancellation?) -> BinaryProcessResult {
        lock.lock(); recorded.append(Call(arguments: args, environment: environment)); lock.unlock()
        let command = Array(args.dropFirst(2))
        func result(_ text: String, status: Int32 = 0) -> BinaryProcessResult {
            BinaryProcessResult(status: status, stdout: Data(text.utf8), stderr: Data(), timedOut: false, outputLimitExceeded: false)
        }
        if mode == "slow" {
            while cancellation?.isCancelled != true { Thread.sleep(forTimeInterval: 0.01) }
            return result("", status: -999)
        }
        if mode == "fail" { return result("PRIVATE stderr /Users/person/file 10.0.0.1", status: 1) }
        if command == ["get-state"] { return result(mode == "offline" ? "offline" : "device\n") }
        if command == ["exec-out", "screencap", "-p"] {
            return BinaryProcessResult(status: 0, stdout: mode == "badPNG" ? Data("not png".utf8) : png,
                stderr: Data(), timedOut: mode == "timeout", outputLimitExceeded: mode == "overflow")
        }
        if command.last == "ro.build.version.sdk" { return result(mode == "oldAndroid" ? "27" : "36") }
        if command.last == "ro.build.version.release" { return result("16") }
        if command.last == "ro.product.model" { return result("Mock Phone") }
        if command == ["shell", "wm", "size"] { return result("Physical size: 1080x2400\nOverride size: 720x1600") }
        if command.first == "push" { stagedBytes = try? Data(contentsOf: URL(fileURLWithPath: command[1])) }
        if command.first == "install" { return result("Success\n") }
        return result("")
    }
}

@main
struct DeviceToolsChecks {
    @MainActor private static var count = 0
    @MainActor private static func expect(_ value: @autoclosure () -> Bool, _ label: String) {
        guard value() else { fatalError("FAIL: " + label) }
        count += 1
        print("PASS: " + label)
    }
    @MainActor private static func rejects(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("FAIL: " + label) }
        catch { expect(true, label) }
    }
    private static func png(width: Int = 320, height: Int = 640) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @MainActor static func main() async throws {
        // A real direct child (no shell/descendants) makes shutdown ownership
        // and SIGTERM escalation observable without touching a phone or ADB.
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--owned-test-child" {
            signal(SIGTERM, CommandLine.arguments[3] == "ignore-term" ? SIG_IGN : SIG_DFL)
            try String(getpid()).write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
            return
        }
        let parent = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MIRRORLINK_TEST_ROOT"]!)
        let root = try ToolFileSafety.temporaryDirectory(in: parent)
        defer { try? FileManager.default.removeItem(at: root) }
        let frame = png(), fixture = root.appendingPathComponent("fixture.png")
        try frame.write(to: fixture)
        let paths = ToolPaths(root: root, adb: URL(fileURLWithPath: "/bin/cat"),
            scrcpy: URL(fileURLWithPath: "/bin/cat"), server: fixture)
        let mock = MockADB(); mock.png = frame
        let service = DeviceToolsService(paths: paths, temporaryRoot: root) { args, env, timeout, limit, token in
            mock.run(args, env, timeout, limit, token)
        }
        let device = AndroidDevice(serial: "192.168.2.3:38123", model: "Mock Phone", product: nil,
            transport: "Wi-Fi", state: .ready, adbSocket: "tcp:5038", hardwareSerial: "SecretSerial123")
        let output = root.appendingPathComponent("captures", isDirectory: true)
        let screenshot = try service.captureScreenshot(for: device, directory: output, cancellation: nil)
        let savedFrame = try Data(contentsOf: screenshot)
        expect(savedFrame == frame, "screenshot preserves every binary PNG byte")
        expect(frame.contains(0) && frame.contains(where: { $0 > 127 }), "PNG fixture includes non-text bytes")
        let second = try service.captureScreenshot(for: device, directory: output, cancellation: nil)
        expect(second != screenshot && FileManager.default.fileExists(atPath: screenshot.path), "screenshots use independent non-overwriting names")
        expect(mock.calls.allSatisfy { $0.arguments.prefix(2) == ["-s", device.serial] && $0.environment["ADB_SERVER_SOCKET"] == "tcp:5038" }, "all ADB commands bind exact serial and daemon")
        expect(mock.calls.contains { $0.arguments.suffix(3) == ["exec-out", "screencap", "-p"] }, "screenshot uses exec-out without a device file")
        expect(!mock.calls.contains { $0.arguments.contains("pull") }, "screenshot never writes/pulls a remote screenshot")
        mock.mode = "badPNG"
        rejects("invalid PNG is rejected") { _ = try service.captureScreenshot(for: device, directory: output, cancellation: nil) }
        mock.mode = "timeout"
        rejects("screenshot timeout is rejected") { _ = try service.captureScreenshot(for: device, directory: output, cancellation: nil) }
        mock.mode = "overflow"
        rejects("oversized screenshot output is rejected") { _ = try service.captureScreenshot(for: device, directory: output, cancellation: nil) }
        mock.mode = "normal"
        rejects("screenshot unwritable/non-directory destination fails") { _ = try service.captureScreenshot(for: device, directory: fixture, cancellation: nil) }
        let cancel = ProcessCancellation(); cancel.cancel(); mock.clear()
        rejects("cancelled screenshot cannot start ADB") { _ = try service.captureScreenshot(for: device, directory: output, cancellation: cancel) }
        expect(mock.calls.isEmpty, "pre-cancelled capture issued no device command")
        expect(!DeviceToolsService.isCompletePNG(frame.dropLast(1)), "truncated PNG is rejected")
        let unauthorized = AndroidDevice(serial: "other", model: nil, product: nil, transport: "USB", state: .unauthorized, adbSocket: nil)
        rejects("unauthorized selected phone is rejected") { try service.home(for: unauthorized, cancellation: nil) }

        let hostile = root.appendingPathComponent("hello ';$(do-not-run)&.txt")
        let payload = Data([0, 128, 255, 1]); try payload.write(to: hostile)
        mock.clear()
        let remote = try service.sendFile(hostile, to: device, cancellation: nil)
        expect(mock.stagedBytes == payload, "file transfer stages exact selected file bytes")
        expect(remote.hasPrefix("/sdcard/Download/MirrorLink/MirrorLink-") && remote.hasSuffix(".txt"), "transfer destination is scoped and uniquely named")
        expect(!remote.contains("$") && !remote.contains("'") && !remote.contains(";"), "hostile local filename cannot become a remote shell argument")
        expect(!mock.calls.flatMap(\.arguments).contains(hostile.path), "original untrusted local basename never enters ADB arguments")
        let another = try service.sendFile(hostile, to: device, cancellation: nil)
        expect(remote != another, "repeated sends cannot overwrite each other")
        let apk = root.appendingPathComponent("chosen.apk"); try payload.write(to: apk)
        mock.clear()
        rejects("ordinary send cannot silently install APK") { _ = try service.sendFile(apk, to: device, cancellation: nil) }
        rejects("APK installation requires explicit confirmation") { try service.installAPK(apk, to: device, confirmed: false, cancellation: nil) }
        expect(mock.calls.isEmpty, "unconfirmed APK issued no device command")
        try service.installAPK(apk, to: device, confirmed: true, cancellation: nil)
        expect(mock.calls.contains { $0.arguments.dropFirst(2).first == "install" }, "confirmed APK uses dedicated install command")
        expect(!mock.calls.contains { $0.arguments.contains("-r") }, "APK install does not silently replace an existing app")
        let link = root.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture)
        rejects("sending a symbolic link is rejected") { _ = try service.sendFile(link, to: device, cancellation: nil) }
        rejects("sending a directory is rejected") { _ = try service.sendFile(output, to: device, cancellation: nil) }
        mock.mode = "fail"
        rejects("failed ADB push cannot report success") { _ = try service.sendFile(hostile, to: device, cancellation: nil) }
        mock.mode = "normal"; mock.clear()
        let health = try service.healthCheck(for: device, cancellation: nil)
        expect(health.isReady && health.androidVersion == "16" && health.model == "Mock Phone", "health reads selected device state and whitelisted properties")
        expect(health.screenSize == "720×1600", "health uses Android override size when present")
        expect(mock.calls.allSatisfy { !$0.arguments.contains("keyevent") && !$0.arguments.contains("push") && !$0.arguments.contains("install") }, "health commands are read-only")
        mock.mode = "offline"; mock.clear()
        let offline = try service.healthCheck(for: device, cancellation: nil)
        expect(!offline.isReady && mock.calls.count == 1, "offline health stops after exact target get-state")
        expect(offline.items.contains { $0.suggestion != nil }, "failed health provides an actionable suggestion")
        mock.mode = "normal"; mock.clear()
        try service.home(for: device, cancellation: nil)
        expect(mock.calls.last!.arguments.suffix(4) == ["shell", "input", "keyevent", "3"], "home sends Android KEYCODE_HOME")
        mock.clear(); try service.openAppDrawer(for: device, cancellation: nil)
        expect(mock.calls.suffix(2).map { Array($0.arguments.suffix(4)) } == [["shell", "input", "keyevent", "3"], ["shell", "input", "keyevent", "284"]], "drawer sends HOME then API-28 ALL_APPS")
        mock.mode = "oldAndroid"; mock.clear()
        rejects("old Android rejects unsupported ALL_APPS") { try service.openAppDrawer(for: device, cancellation: nil) }
        expect(!mock.calls.contains { $0.arguments.contains("284") }, "unsupported ALL_APPS is never issued")
        mock.mode = "normal"; mock.png = png(width: 640, height: 320); mock.clear()
        try service.swipeUpForDrawer(for: device, cancellation: nil)
        expect(Array(mock.calls.last!.arguments.suffix(8)) == ["shell", "input", "swipe", "320", "249", "320", "70", "350"], "drawer fallback uses current PNG orientation and central 78%-22% swipe")
        expect(!mock.calls.contains { $0.arguments.contains("wm") }, "drawer fallback does not mistake natural wm size for current orientation")

        let report = FeedbackReport(appVersion: "0.4.5", build: "10", device: device, health: health,
            session: FeedbackSessionSnapshot(state: "mirroring", quality: "Ultra", videoSize: "1080×2400", failure: "secret raw logs"))
        expect(!report.preview.contains(device.serial) && !report.preview.contains("SecretSerial123") && !report.preview.contains("secret raw logs"), "feedback excludes device IDs, addresses and raw errors")
        let privateText = "serial=SecretSerial123\n192.168.2.3:38123\n2001:db8::1234\n/Users/alice/private/file\nWIFI:T:ADB;S:service;P:password;;\napi_key=private-key\nmac=aa:bb:cc:dd:ee:ff"
        let redacted = FeedbackRedactor.redact(privateText, knownIdentifiers: ["SecretSerial123"])
        expect(!["SecretSerial123", "192.168.2.3", "2001:db8", "/Users/alice", "password", "private-key", "aa:bb:cc"].contains(where: redacted.contains), "feedback redacts IDs, IPv4/IPv6/MAC, local paths and credentials")
        let archive = root.appendingPathComponent("feedback.zip")
        _ = try FeedbackExportService.export(report: report, attachments: [fixture], destination: archive)
        let list = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", archive.path], timeout: 5)
        let names = String(decoding: list.stdout, as: UTF8.self)
        expect(list.succeeded && names.contains("diagnostics.txt") && names.contains("attachment-1.png") && !names.contains("fixture.png"), "feedback ZIP contains only diagnostics and explicitly chosen anonymous-named media")
        let extracted = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", archive.path, "diagnostics.txt"], timeout: 5)
        expect(String(decoding: extracted.stdout, as: UTF8.self) == report.preview, "exported diagnostics exactly match local preview")
        let oldBytes = try Data(contentsOf: archive)
        rejects("feedback cannot overwrite an existing ZIP") { _ = try FeedbackExportService.export(report: report, attachments: [], destination: archive) }
        let preservedArchive = try Data(contentsOf: archive)
        expect(preservedArchive == oldBytes, "existing feedback archive remains intact")
        rejects("feedback does not follow symbolic-link attachments") { _ = try FeedbackExportService.export(report: report, attachments: [link], destination: root.appendingPathComponent("link.zip")) }
        rejects("feedback rejects non-media attachments") { _ = try FeedbackExportService.export(report: report, attachments: [hostile], destination: root.appendingPathComponent("text.zip")) }
        let emptyArchive = root.appendingPathComponent("diagnostics-only.zip")
        _ = try FeedbackExportService.export(report: report, attachments: [], destination: emptyArchive)
        let noMedia = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", emptyArchive.path], timeout: 5)
        expect(!String(decoding: noMedia.stdout, as: UTF8.self).contains("attachment"), "default feedback has no screen or media files")
        rejects("cancelled feedback export cannot complete") { _ = try FeedbackExportService.export(report: report, attachments: [], destination: root.appendingPathComponent("cancelled.zip"), cancellation: cancel) }

        let binary = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [fixture.path], timeout: 3)
        expect(binary.succeeded && binary.stdout == frame, "real subprocess pipe preserves binary output")
        let large = root.appendingPathComponent("large.bin"); try Data(repeating: 255, count: 2_097_152).write(to: large)
        let bounded = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [large.path], timeout: 3, outputLimit: 1024)
        expect(bounded.outputLimitExceeded && bounded.stdout.count == 1024, "real subprocess output is bounded")
        let start = Date()
        let timeout = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.05)
        expect(timeout.timedOut && Date().timeIntervalSince(start) < 2, "real subprocess timeout terminates promptly")
        let runningCancel = ProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { runningCancel.cancel() }
        let stopped = BoundedProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 10, cancellation: runningCancel)
        expect(stopped.status == -999 && !stopped.timedOut, "real subprocess cancellation is distinct from timeout")

        let suite = "MirrorLink.device-tools-checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceToolsStore(paths: paths, defaults: defaults, outputDirectory: output, service: service)
        let selected = root.appendingPathComponent("selected-output")
        try store.setOutputDirectory(selected)
        expect(defaults.string(forKey: DeviceToolsStore.directoryPreferenceKey) == selected.path, "chosen output folder is persisted")
        let restored = DeviceToolsStore(paths: paths, defaults: defaults)
        expect(restored.outputDirectory.standardizedFileURL.path == selected.standardizedFileURL.path, "output folder restores without a maintainer path")
        mock.mode = "slow"; mock.clear()
        store.captureScreenshot(for: device)
        expect(store.isBusy(for: device.id), "store publishes per-device processing state")
        store.captureScreenshot(for: device)
        try await Task.sleep(nanoseconds: 50_000_000)
        expect(mock.calls.count == 1, "busy device cannot start duplicate operations")
        store.cancel(for: device.id)
        for _ in 0..<100 where store.isBusy(for: device.id) { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(!store.isBusy(for: device.id) && store.lastScreenshotURL(for: device.id) == nil, "store cancellation produces no late screenshot result")
        expect(store.status(for: device.id) == DeviceToolsError.cancelled.message.resolved, "store retains a localized cancellation message")
        store.captureScreenshot(for: device)
        try await Task.sleep(nanoseconds: 30_000_000)
        store.shutdown()
        let statusAtShutdown = store.status(for: device.id)
        try await Task.sleep(nanoseconds: 80_000_000)
        expect(!store.isBusy(for: device.id) && store.status(for: device.id) == statusAtShutdown, "shutdown cancels workers and suppresses late callbacks")
        let callsAtShutdown = mock.calls.count
        store.home(for: device)
        try await Task.sleep(nanoseconds: 30_000_000)
        expect(mock.calls.count == callsAtShutdown, "shutdown store cannot start new device operations")

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let completedWorkers = CompletedToolWorkers()
        let shutdownService = DeviceToolsService(paths: paths, temporaryRoot: root) { args, _, _, _, token in
            defer { completedWorkers.finish() }
            let name = args[1]
            return BoundedProcessRunner.run(executable: executable,
                arguments: ["--owned-test-child", root.appendingPathComponent(name + ".pid").path,
                            name == "shutdown-two" ? "ignore-term" : "term"],
                timeout: 10, cancellation: token)
        }
        let shutdownStore = DeviceToolsStore(paths: paths, defaults: defaults, outputDirectory: output,
            service: shutdownService, feedbackExporter: { _, _, destination, token in
                defer { completedWorkers.finish() }
                let result = BoundedProcessRunner.run(executable: executable,
                    arguments: ["--owned-test-child", root.appendingPathComponent("feedback.pid").path, "ignore-term"],
                    timeout: 10, cancellation: token)
                guard result.succeeded else { throw DeviceToolsError.cancelled }
                return destination
            })
        let firstDevice = AndroidDevice(serial: "shutdown-one", model: nil, product: nil,
            transport: "USB", state: .ready, adbSocket: nil)
        let secondDevice = AndroidDevice(serial: "shutdown-two", model: nil, product: nil,
            transport: "USB", state: .ready, adbSocket: nil)
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["8"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() }; unrelated.waitUntilExit() }
        shutdownStore.home(for: firstDevice)
        shutdownStore.home(for: secondDevice)
        shutdownStore.exportFeedback(report, attachments: [], to: root.appendingPathComponent("shutdown-feedback.zip"))
        expect(shutdownStore.isBusy(for: firstDevice.id) && shutdownStore.isBusy(for: secondDevice.id)
            && shutdownStore.feedbackIsBusy, "different devices and feedback can have simultaneous owned commands")
        let markers = ["shutdown-one.pid", "shutdown-two.pid", "feedback.pid"].map { root.appendingPathComponent($0) }
        for _ in 0..<200 {
            if markers.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(markers.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "all real shutdown-test children started before cancellation")
        let ownedPIDs = try markers.map { url -> pid_t in
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let pid = pid_t(text), pid > 0 else { fatalError("invalid owned-child fixture PID") }
            return pid
        }
        let shutdownStarted = Date()
        // This deliberately blocks MainActor: success cannot depend on any
        // DispatchQueue.main completion callback or a cooperative run loop.
        shutdownStore.shutdown()
        expect(Date().timeIntervalSince(shutdownStarted) < 3.5, "shutdown uses a bounded wait even when children ignore SIGTERM")
        expect(completedWorkers.count == 3, "shutdown waits for all device and feedback workers without main-queue callbacks")
        expect(ownedPIDs.allSatisfy { kill($0, 0) == -1 && errno == ESRCH }, "shutdown returns only after real owned children are reaped, including SIGTERM-ignoring children")
        expect(unrelated.isRunning, "shutdown does not terminate an unrelated process")
        expect(!shutdownStore.isBusy(for: firstDevice.id) && !shutdownStore.isBusy(for: secondDevice.id)
            && !shutdownStore.feedbackIsBusy && shutdownStore.lastFeedbackURL == nil, "shutdown clears per-device and feedback state without publishing a cancelled export")
        let shutdownStatus = shutdownStore.status(for: firstDevice.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        expect(shutdownStore.status(for: firstDevice.id) == shutdownStatus && shutdownStore.lastFeedbackURL == nil,
            "queued main-queue completions remain invalid after synchronous shutdown")

        let lateToken = ProcessCancellation()
        lateToken.cancel()
        let lateChild = Process()
        lateChild.executableURL = URL(fileURLWithPath: "/bin/sleep")
        lateChild.arguments = ["8"]
        try lateChild.run()
        let lateStarted = Date()
        lateToken.registerOwnedProcess(lateChild)
        lateChild.waitUntilExit()
        lateToken.unregisterOwnedProcess(lateChild)
        expect(!lateChild.isRunning && Date().timeIntervalSince(lateStarted) < 1,
            "registration after cancellation immediately terminates the exact newly launched child")

        let forceMarker = root.appendingPathComponent("force-owned.pid")
        let forceChild = Process()
        forceChild.executableURL = executable
        forceChild.arguments = ["--owned-test-child", forceMarker.path, "ignore-term"]
        try forceChild.run()
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: forceMarker.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(FileManager.default.fileExists(atPath: forceMarker.path), "force-termination fixture has installed its SIGTERM handler")
        let forceToken = ProcessCancellation()
        forceToken.registerOwnedProcess(forceChild)
        forceToken.cancel()
        try await Task.sleep(nanoseconds: 30_000_000)
        expect(forceChild.isRunning, "force-termination fixture really ignores cooperative SIGTERM")
        forceToken.forceTerminateOwnedProcesses()
        forceChild.waitUntilExit()
        forceToken.unregisterOwnedProcess(forceChild)
        expect(!forceChild.isRunning && unrelated.isRunning,
            "shutdown fallback force-terminates only the registered running Process instance")
        print("Device tools checks: \(count) passed (mock/local processes; no real phone accessed).")
    }
}
