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

private final class ToolProgressMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return messages }
    func append(_ message: LocalizedMessage) { lock.lock(); messages.append(message.resolved); lock.unlock() }
}

private final class MockADB: @unchecked Sendable {
    struct Call { let arguments: [String]; let environment: [String: String]; let timeout: TimeInterval; let hasCancellation: Bool }
    private let lock = NSLock()
    private var recorded: [Call] = []
    var mode = "normal"
    var png = Data()
    var stagedBytes: Data?
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }
    func clear() { lock.lock(); recorded = []; lock.unlock() }
    func run(_ args: [String], _ environment: [String: String], _ timeout: TimeInterval, _ limit: Int,
             _ cancellation: ProcessCancellation?) -> BinaryProcessResult {
        lock.lock(); recorded.append(Call(arguments: args, environment: environment, timeout: timeout,
                                          hasCancellation: cancellation != nil)); lock.unlock()
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
        if command.last == "ro.build.version.sdk" { return result(mode == "legacyAndroid" ? "21" : mode == "oldAndroid" ? "27" : "36") }
        if command.contains("resolve-activity") {
            if mode == "vivoLauncher" { return result("priority=0 isDefault=true\ncom.android.launcher3/com.bbk.launcher2.Launcher\n") }
            if mode == "launcherQueryFailed" { return result("", status: 1) }
            return result("com.example.launcher/.Home\n")
        }
        if command.last == "ro.build.version.release" { return result("16") }
        if command.last == "ro.product.model" { return result("Mock Phone") }
        if command == ["shell", "wm", "size"] { return result("Physical size: 1080x2400\nOverride size: 720x1600") }
        if command.first == "push" {
            stagedBytes = try? Data(contentsOf: URL(fileURLWithPath: command[command.contains("-z") ? 3 : 1]))
            if mode == "wirelessTransferTimeout" {
                return BinaryProcessResult(status: 15, stdout: Data(), stderr: Data(), timedOut: true, outputLimitExceeded: false)
            }
            if mode == "cancelWirelessTransfer" { cancellation?.cancel(); return result("", status: -999) }
        }
        if command.first == "install" || command.starts(with: ["shell", "cmd", "package", "install"]) {
            if command.first == "install" { stagedBytes = try? Data(contentsOf: URL(fileURLWithPath: command.last!)) }
            if mode == "parseFileError" { return result("Exception: Failed to parse APK file: PRIVATE /Users/person/file", status: 255) }
            if mode == "slowInstall" {
                while cancellation?.isCancelled != true { Thread.sleep(forTimeInterval: 0.01) }
                return result("", status: -999)
            }
            if mode == "installTimeout" {
                return BinaryProcessResult(status: 15, stdout: Data(), stderr: Data(), timedOut: true, outputLimitExceeded: false)
            }
            if mode.hasPrefix("INSTALL_") { return result("Failure [\(mode)] PRIVATE /Users/person/file", status: 1) }
            return result("Success\n")
        }
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
        if CommandLine.arguments.contains("--benchmark-staging") {
            let source = root.appendingPathComponent("synthetic-128MiB.apk")
            try ToolFileSafety.writeExclusive(Data(), to: source)
            let handle = try FileHandle(forWritingTo: source)
            let block = Data(repeating: 0x5A, count: 1_048_576)
            for _ in 0..<128 { try handle.write(contentsOf: block) }
            try handle.close()
            for preferClone in [false, true] {
                var samples: [Double] = []
                for index in 0..<3 {
                    let target = root.appendingPathComponent("sample-\(preferClone)-\(index).apk")
                    let start = ProcessInfo.processInfo.systemUptime
                    try ToolFileSafety.copyRegularFile(source, to: target, cancellation: nil, preferClone: preferClone)
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
                print("BENCHMARK 128 MiB staging \(preferClone ? "clone preferred" : "byte copy"): \(samples.map { String(format: "%.2f ms", $0) }.joined(separator: ", "))")
            }
            return
        }
        let frame = png(), fixture = root.appendingPathComponent("fixture.png")
        try frame.write(to: fixture)
        let paths = ToolPaths(root: root, adb: URL(fileURLWithPath: "/bin/cat"),
            scrcpy: URL(fileURLWithPath: "/bin/cat"), server: fixture)
        let mock = MockADB(); mock.png = frame
        let service = DeviceToolsService(paths: paths, temporaryRoot: root) { args, env, timeout, limit, token in
            mock.run(args, env, timeout, limit, token)
        }
        let device = AndroidDevice(serial: "usb-install-target", model: "Mock Phone", product: nil,
            transport: "USB", state: .ready, adbSocket: "tcp:5038", hardwareSerial: "SecretSerial123")
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
        let readable = root.appendingPathComponent("会议资料-2026.txt")
        try Data("readable filename".utf8).write(to: readable)
        let readableRemote = try service.sendFile(readable, to: device, cancellation: nil)
        expect(readableRemote.hasSuffix("-会议资料-2026.txt"), "safe original filename remains readable on the phone")
        let apk = root.appendingPathComponent("chosen.apk"); try payload.write(to: apk)
        mock.clear()
        rejects("ordinary send cannot silently install APK") { _ = try service.sendFile(apk, to: device, cancellation: nil) }
        rejects("APK installation requires explicit confirmation") { try service.installAPK(apk, to: device, confirmed: false, cancellation: nil) }
        expect(mock.calls.isEmpty, "unconfirmed APK issued no device command")
        let progress = ToolProgressMessages()
        try service.installAPK(apk, to: device, confirmed: true, cancellation: nil, progress: { progress.append($0) })
        expect(mock.calls.contains { $0.arguments.dropFirst(2).first == "install" }, "confirmed APK uses dedicated install command")
        expect(mock.calls.last?.arguments.dropFirst(2).dropLast() == ["install", "--streaming", "--no-incremental", "--no-fastdeploy", "-R"], "APK selects one streaming attempt and explicitly prohibits replacement")
        expect(mock.stagedBytes == payload, "fast APK staging preserves the exact selected bytes")
        expect(progress.values == [L10n.tr("正在检查手机连接…"), L10n.tr("正在准备 APK…"), L10n.tr("正在传输并安装 APK…")], "installation reports real phases without invented percentages")
        expect(!FileManager.default.fileExists(atPath: mock.calls.last!.arguments.last!), "successful install removes its private local staging file")
        mock.mode = "installTimeout"; mock.clear()
        do { try service.installAPK(apk, to: device, confirmed: true, cancellation: nil); fatalError("expected install timeout") }
        catch let error as DeviceToolsError { expect(error.localizedDescription == DeviceToolsError.apkTimedOut.localizedDescription, "install timeout asks to check the phone before retrying") }
        expect(mock.calls.filter { $0.arguments.contains("install") }.count == 1, "timeout never retries an ambiguous installation automatically")
        expect(!FileManager.default.fileExists(atPath: mock.calls.last!.arguments.last!), "timed-out install removes its private local staging file")
        mock.mode = "oldAndroid"; mock.clear()
        try service.installAPK(apk, to: device, confirmed: true, cancellation: nil)
        expect(mock.calls.last!.arguments.contains("--streaming") && !mock.calls.last!.arguments.contains("-R") && !mock.calls.last!.arguments.contains("-r"),
               "Android 7-8 streaming retains its default no-replacement behavior")
        mock.mode = "legacyAndroid"; mock.clear()
        try service.installAPK(apk, to: device, confirmed: true, cancellation: nil)
        expect(!mock.calls.last!.arguments.contains("--streaming") && !mock.calls.last!.arguments.contains("-R") && !mock.calls.last!.arguments.contains("-r"),
               "older USB phones retain compatible legacy installation without replacement")
        for (code, expected) in [("INSTALL_PARSE_FAILED_NOT_APK", DeviceToolsError.apkInvalid),
            ("INSTALL_FAILED_ALREADY_EXISTS", .apkConflict), ("INSTALL_FAILED_USER_RESTRICTED", .apkBlocked),
            ("INSTALL_FAILED_NO_MATCHING_ABIS", .apkIncompatible)] {
            mock.mode = code
            do { try service.installAPK(apk, to: device, confirmed: true, cancellation: nil); fatalError("expected install rejection") }
            catch let error as DeviceToolsError { expect(error.localizedDescription == expected.localizedDescription && !error.localizedDescription.contains("PRIVATE"), "APK failure \(code) gives actionable localized guidance without raw private output") }
        }
        let wireless = AndroidDevice(serial: "wireless-install-target", model: nil, product: nil, transport: "Wi-Fi",
                                     state: .ready, adbSocket: "localfilesystem:/tmp/mock-wireless-adb")
        mock.mode = "normal"; mock.clear()
        let wirelessProgress = ToolProgressMessages()
        try service.installAPK(apk, to: wireless, confirmed: true, cancellation: nil, progress: { wirelessProgress.append($0) })
        let wifiCalls = mock.calls
        let push = wifiCalls.first { $0.arguments.contains("push") }!
        let remoteAPK = push.arguments.last!
        expect(Array(push.arguments.dropFirst(2).prefix(3)) == ["push", "-z", "any"], "Wi-Fi APK transfer negotiates ADB compression")
        expect(remoteAPK.hasPrefix("/data/local/tmp/MirrorLink-install-") && remoteAPK.hasSuffix(".apk") && !remoteAPK.contains(apk.lastPathComponent),
               "wireless installer uses only its own unpredictable remote APK name")
        expect(wifiCalls.allSatisfy { $0.arguments.prefix(2) == ["-s", wireless.serial] && $0.environment["ADB_SERVER_SOCKET"] == wireless.adbSocket },
               "compressed transfer installation and cleanup remain on the exact wireless route")
        expect(wifiCalls.contains { Array($0.arguments.dropFirst(2)) == ["shell", "cmd", "package", "install", "-R", remoteAPK] },
               "wireless installation runs only after push and explicitly rejects replacement")
        expect(Array(wifiCalls.last!.arguments.dropFirst(2)) == ["shell", "rm", "-f", remoteAPK] && wifiCalls.last!.timeout == 1.5 && !wifiCalls.last!.hasCancellation,
               "wireless cleanup removes one exact owned file with an independent bounded wait")
        expect(wirelessProgress.values.suffix(2) == [L10n.tr("正在传输 APK…"), L10n.tr("正在手机上安装 APK…")],
               "wireless feedback separates completed transfer from phone installation")
        expect(!FileManager.default.fileExists(atPath: push.arguments[5]), "wireless installation also removes its local staging file")
        mock.clear()
        try service.installAPK(apk, to: wireless, confirmed: true, cancellation: nil)
        expect(mock.calls.first { $0.arguments.contains("push") }!.arguments.last != remoteAPK, "each wireless APK gets a distinct temporary destination")
        for (mode, failure) in [("wirelessTransferTimeout", DeviceToolsError.apkTransferTimedOut),
                                ("installTimeout", .apkTimedOut), ("INSTALL_FAILED_USER_RESTRICTED", .apkBlocked),
                                ("INSTALL_PARSE_FAILED_NOT_APK", .apkInvalid), ("parseFileError", .apkInvalid), ("INSTALL_FAILED_ALREADY_EXISTS", .apkConflict)] {
            mock.mode = mode; mock.clear()
            do { try service.installAPK(apk, to: wireless, confirmed: true, cancellation: nil); fatalError("expected wireless error") }
            catch let error as DeviceToolsError { expect(error.localizedDescription == failure.localizedDescription, "wireless \(mode) has the correct actionable failure") }
            expect(mock.calls.last!.arguments.contains("rm"), "wireless \(mode) still attempts exact-file cleanup")
            if mode == "wirelessTransferTimeout" {
                expect(!mock.calls.contains { $0.arguments.contains("install") }, "incomplete transfer cannot initiate phone installation")
            }
        }
        mock.mode = "cancelWirelessTransfer"; mock.clear()
        let transferCancellation = ProcessCancellation()
        rejects("wireless transfer can be cancelled") {
            try service.installAPK(apk, to: wireless, confirmed: true, cancellation: transferCancellation)
        }
        expect(!mock.calls.contains { $0.arguments.contains("install") } && mock.calls.last!.arguments.contains("rm") && !mock.calls.last!.hasCancellation,
               "cancelled wireless transfer never installs but can still clean its owned partial file")
        mock.mode = "normal"
        let link = root.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture)
        rejects("sending a symbolic link is rejected") { _ = try service.sendFile(link, to: device, cancellation: nil) }
        rejects("sending a directory is rejected") { _ = try service.sendFile(output, to: device, cancellation: nil) }
        let snapshot = root.appendingPathComponent("snapshot.apk")
        try ToolFileSafety.copyRegularFile(apk, to: snapshot, cancellation: nil, preferClone: true)
        try Data("changed source".utf8).write(to: apk)
        let snapshotBytes = try Data(contentsOf: snapshot)
        expect(snapshotBytes == payload, "cloned snapshot is independent of later source edits")
        rejects("clone staging cannot replace an existing destination") {
            try ToolFileSafety.copyRegularFile(apk, to: snapshot, cancellation: nil, preferClone: true)
        }
        let preservedBytes = try Data(contentsOf: snapshot)
        expect(preservedBytes == payload, "existing destination survives a failed clone attempt")
        rejects("clone staging rejects symbolic links") {
            try ToolFileSafety.copyRegularFile(link, to: root.appendingPathComponent("bad-clone"), cancellation: nil, preferClone: true)
        }
        rejects("clone staging enforces its file size cap before cloning") {
            try ToolFileSafety.copyRegularFile(apk, to: root.appendingPathComponent("oversized-clone"), cancellation: nil, maximumBytes: 1, preferClone: true)
        }
        let cancelledClone = ProcessCancellation(); cancelledClone.cancel()
        rejects("clone staging obeys pre-cancellation") {
            try ToolFileSafety.copyRegularFile(apk, to: root.appendingPathComponent("cancelled-clone"), cancellation: cancelledClone, preferClone: true)
        }
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
        mock.mode = "vivoLauncher"; mock.clear()
        try service.openAppDrawer(for: device, cancellation: nil)
        expect(mock.calls.contains { $0.arguments.contains("swipe") } && !mock.calls.contains { $0.arguments.contains("284") }, "verified vivo HOME component automatically uses the working swipe route")
        expect(mock.calls.allSatisfy { $0.arguments.prefix(2) == ["-s", device.serial] && $0.environment["ADB_SERVER_SOCKET"] == device.adbSocket }, "launcher query and automatic swipe remain bound to selected phone and ADB route")
        expect(DeviceToolsService.prefersSwipeForDrawer(homeResolution: "com.android.launcher3/com.bbk.launcher2.Launcher\n"), "exact resolved launcher selects compatibility")
        for resolution in ["", "com.android.launcher3/.Launcher", "com.example.launcher/.Home", "other/com.bbk.launcher2.Launcher", "com.android.launcher3/com.bbk.launcher2.LauncherExtra", "com.android.launcher3/com.bbk.launcher2.Launcher\nother/.Home"] {
            expect(!DeviceToolsService.prefersSwipeForDrawer(homeResolution: resolution), "unverified or ambiguous HOME component retains standard behavior")
        }
        mock.mode = "launcherQueryFailed"; mock.clear()
        try service.openAppDrawer(for: device, cancellation: nil)
        expect(mock.calls.last!.arguments.suffix(4) == ["shell", "input", "keyevent", "284"], "unavailable launcher query preserves standard ALL_APPS route")
        mock.clear()
        rejects("cancelled drawer operation starts no device commands") { try service.openAppDrawer(for: device, cancellation: cancel) }
        expect(mock.calls.isEmpty, "cancelled drawer cannot issue launcher query or gesture")
        mock.mode = "normal"

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
        mock.mode = "slowInstall"
        store.installAPK(apk, to: device, confirmed: true)
        for _ in 0..<100 where store.status(for: device.id)?.contains(L10n.tr("正在传输并安装 APK…")) != true { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(store.isBusy(for: device.id) && (store.windowState(for: device)["installStatus"] as? String)?.contains("0") == true,
               "active APK publishes an inline phase and elapsed time to the mirror window")
        let resultID = store.windowState(for: device)["resultID"] as? String
        store.cancel(for: device.id)
        for _ in 0..<100 where store.isBusy(for: device.id) { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(store.isError(for: device.id) && store.status(for: device.id)?.contains("不会撤销") == true,
               "cancelled APK explains that completed phone installation is not undone")
        mock.mode = "normal"
        store.installAPK(apk, to: device, confirmed: true)
        for _ in 0..<100 where store.isBusy(for: device.id) { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(!store.isError(for: device.id) && store.status(for: device.id)?.contains("安装完成") == true,
               "APK completion publishes a visible result with elapsed time")
        expect(store.windowState(for: device)["resultID"] as? String != resultID, "new install gets a new identity for late-progress suppression")
        mock.mode = "slow"; mock.clear()
        store.captureScreenshot(for: device)
        expect(store.windowState(for: device)["installStatus"] as? String == "", "next unrelated operation removes APK-specific feedback")
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
