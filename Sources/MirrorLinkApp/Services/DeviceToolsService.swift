import Foundation
import ImageIO

enum DeviceToolsError: Error, LocalizedError, Sendable {
    case toolsMissing, invalidTarget, deviceNotReady, cancelled, timedOut, outputTooLarge
    case commandFailed, invalidPNG, invalidFile, saveFailed, apkRequiresConfirmation
    case apkOnly, drawerUnsupported, invalidScreenSize, invalidAttachment
    case apkInvalid, apkConflict, apkBlocked, apkIncompatible, apkTimedOut, apkTransferTimedOut
    var message: LocalizedMessage {
        switch self {
        case .toolsMissing: return L10n.message("内置工具不可用，请重新安装完整应用。")
        case .invalidTarget: return L10n.message("未能确认目标手机，请重新选择设备。")
        case .deviceNotReady: return L10n.message("手机尚未就绪，请解锁手机并确认调试授权。")
        case .cancelled: return L10n.message("操作已取消。")
        case .timedOut: return L10n.message("操作超时，请检查连接后重试。")
        case .outputTooLarge: return L10n.message("设备返回的数据过大，已停止操作。")
        case .commandFailed: return L10n.message("操作未完成，请检查手机连接、可用空间和系统提示后重试。")
        case .invalidPNG: return L10n.message("未获取到完整的 PNG 截图，请重试。")
        case .invalidFile: return L10n.message("请选择不超过 2 GB 的普通文件；不支持文件夹或符号链接。")
        case .saveFailed: return L10n.message("无法保存文件，请选择可写的文件夹和未使用的文件名。")
        case .apkRequiresConfirmation: return L10n.message("APK 需要使用“安装 APK”并明确确认，普通文件发送不会安装应用。")
        case .apkOnly: return L10n.message("请选择 APK 安装文件。")
        case .apkInvalid: return L10n.message("这个 APK 已损坏或不是有效安装包，请重新下载后再试。")
        case .apkConflict: return L10n.message("手机上已有这个应用，镜连没有覆盖它。如需更新，请使用该应用自己的更新方式。")
        case .apkBlocked: return L10n.message("手机拒绝了安装，请解锁手机并查看手机上的安装授权提示。")
        case .apkIncompatible: return L10n.message("这个 APK 不兼容当前手机，请选择适用于该手机 Android 版本和处理器的安装包。")
        case .apkTimedOut: return L10n.message("安装等待超时。请查看手机上的安装授权和应用列表，确认结果后再试；停止等待不会撤销已完成的安装。")
        case .apkTransferTimedOut: return L10n.message("APK 传输超时，尚未发起安装。请检查 Wi-Fi 信号或改用 USB 后重试。")
        case .drawerUnsupported: return L10n.message("这台手机不支持标准应用抽屉指令，请使用上滑兼容方式。")
        case .invalidScreenSize: return L10n.message("无法确认屏幕尺寸，请在投屏窗口中手动上滑。")
        case .invalidAttachment: return L10n.message("反馈附件仅支持普通图片或视频文件，最多 8 个，每个不超过 512 MB，总计不超过 1 GB；不支持符号链接。")
        }
    }
    var errorDescription: String? { message.resolved }
}

struct DeviceToolsService: Sendable {
    typealias Executor = @Sendable ([String], [String: String], TimeInterval, Int, ProcessCancellation?) -> BinaryProcessResult
    let paths: ToolPaths
    private let execute: Executor
    private let temporaryRoot: URL

    init(paths: ToolPaths, temporaryRoot: URL = FileManager.default.temporaryDirectory, execute: Executor? = nil) {
        self.paths = paths
        self.temporaryRoot = temporaryRoot
        self.execute = execute ?? { arguments, environment, timeout, limit, cancellation in
            BoundedProcessRunner.run(executable: paths.adb, arguments: arguments, environment: environment,
                                     timeout: timeout, outputLimit: limit, cancellation: cancellation)
        }
    }

    func captureScreenshot(for device: AndroidDevice, directory: URL, cancellation: ProcessCancellation?) throws -> URL {
        try ready(device, cancellation)
        let result = try command(["exec-out", "screencap", "-p"], device, timeout: 20,
                                 limit: 67_108_864, cancellation: cancellation)
        guard Self.isCompletePNG(result.stdout) else { throw DeviceToolsError.invalidPNG }
        do { try ToolFileSafety.prepareDirectory(directory) } catch { throw DeviceToolsError.saveFailed }
        try checkCancellation(cancellation)
        let url = directory.appendingPathComponent("MirrorLink-" + UUID().uuidString + ".png")
        do { try ToolFileSafety.writeExclusive(result.stdout, to: url) } catch { throw DeviceToolsError.saveFailed }
        if cancellation?.isCancelled == true {
            try? FileManager.default.removeItem(at: url)
            throw DeviceToolsError.cancelled
        }
        return url
    }

    func sendFile(_ file: URL, to device: AndroidDevice, cancellation: ProcessCancellation?) throws -> String {
        guard file.pathExtension.lowercased() != "apk" else { throw DeviceToolsError.apkRequiresConfirmation }
        try ready(device, cancellation)
        let directory = try ToolFileSafety.temporaryDirectory(in: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Preserve a readable name, allowing only letters, digits, '-' and '_'.
        // The unique prefix prevents overwrites; shell punctuation is never sent.
        let stem = String(file.deletingPathExtension().lastPathComponent.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }.prefix(60))
        let name = "MirrorLink-" + String(UUID().uuidString.prefix(8)) + "-" + (stem.isEmpty ? "file" : stem) + ToolFileSafety.safeExtension(file)
        let staged = directory.appendingPathComponent(name)
        try ToolFileSafety.copyRegularFile(file, to: staged, cancellation: cancellation)
        let remote = "/sdcard/Download/MirrorLink/" + name
        _ = try command(["shell", "mkdir", "-p", "/sdcard/Download/MirrorLink"], device, cancellation: cancellation)
        _ = try command(["push", staged.path, remote], device, timeout: 300, cancellation: cancellation)
        try checkCancellation(cancellation)
        return remote
    }

    func installAPK(_ file: URL, to device: AndroidDevice, confirmed: Bool,
                    cancellation: ProcessCancellation?,
                    progress: @Sendable (LocalizedMessage) -> Void = { _ in }) throws {
        guard confirmed else { throw DeviceToolsError.apkRequiresConfirmation }
        guard file.pathExtension.lowercased() == "apk" else { throw DeviceToolsError.apkOnly }
        progress(L10n.message("正在检查手机连接…"))
        guard device.state == .ready else { throw DeviceToolsError.deviceNotReady }
        // One successful, targeted query both checks the connection and selects
        // compatible options. Android 9+ replaces by default unless -R is sent;
        // older releases reject replacement by default and do not accept -R.
        let version = try text(["shell", "getprop", "ro.build.version.sdk"], device, cancellation)
        guard let api = Int(version), api >= 21 else { throw DeviceToolsError.deviceNotReady }
        let directory = try ToolFileSafety.temporaryDirectory(in: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: directory) }
        let staged = directory.appendingPathComponent("selected-" + UUID().uuidString + ".apk")
        progress(L10n.message("正在准备 APK…"))
        try ToolFileSafety.copyRegularFile(file, to: staged, cancellation: cancellation, preferClone: true)
        // Android 7+ supports streaming. Earlier USB phones retain ADB's legacy
        // mode. Neither path probes incremental installation or silently retries.
        let mode = api >= 24 ? ["--streaming"] : []
        let replacement = api >= 28 ? ["-R"] : []
        let result: BinaryProcessResult
        if device.isWireless, api >= 30 {
            // Streaming install cannot compress its APK stream. Negotiate ADB
            // sync compression for Wi-Fi; already-compressed files may gain less.
            // This private name is generated here, never derived from user input.
            let remote = "/data/local/tmp/MirrorLink-install-" + UUID().uuidString + ".apk"
            defer {
                // Cancellation must still allow bounded cleanup of this exact
                // owned file. Never reuse a cancelled token or remove a directory.
                _ = try? command(["shell", "rm", "-f", remote], device, timeout: 1.5, cancellation: nil)
            }
            progress(L10n.message("正在传输 APK…"))
            do {
                _ = try command(["push", "-z", "any", staged.path, remote], device, timeout: 300, cancellation: cancellation)
            } catch DeviceToolsError.timedOut { throw DeviceToolsError.apkTransferTimedOut }
            try checkCancellation(cancellation)
            progress(L10n.message("正在手机上安装 APK…"))
            do {
                result = try command(["shell", "cmd", "package", "install"] + replacement + [remote],
                                     device, timeout: 180, cancellation: cancellation, apkInstall: true)
            } catch DeviceToolsError.timedOut { throw DeviceToolsError.apkTimedOut }
        } else {
            progress(L10n.message("正在传输并安装 APK…"))
            do {
                result = try command(["install"] + mode + ["--no-incremental", "--no-fastdeploy"] + replacement + [staged.path],
                                     device, timeout: 180, cancellation: cancellation)
            } catch DeviceToolsError.timedOut { throw DeviceToolsError.apkTimedOut }
        }
        guard String(decoding: result.stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
            .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Success" }) else {
            throw DeviceToolsError.commandFailed
        }
        try checkCancellation(cancellation)
    }

    func home(for device: AndroidDevice, cancellation: ProcessCancellation?) throws {
        try ready(device, cancellation)
        _ = try command(["shell", "input", "keyevent", "3"], device, cancellation: cancellation)
    }

    func openAppDrawer(for device: AndroidDevice, cancellation: ProcessCancellation?) throws {
        try ready(device, cancellation)
        // V2520's stock launcher ignores ALL_APPS but its desktop swipe was
        // verified on-device. Select that route by the resolved HOME component,
        // not the phone brand/model: users may install another launcher.
        let launcherResult = try? command(["shell", "cmd", "package", "resolve-activity", "--brief",
            "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME"],
            device, timeout: 2, cancellation: cancellation)
        try checkCancellation(cancellation)
        let launcher = launcherResult.map { String(decoding: $0.stdout, as: UTF8.self) } ?? ""
        if Self.prefersSwipeForDrawer(homeResolution: launcher) {
            try swipeUpForDrawer(for: device, cancellation: cancellation)
            return
        }
        let version = try text(["shell", "getprop", "ro.build.version.sdk"], device, cancellation)
        guard let api = Int(version), api >= 28 else { throw DeviceToolsError.drawerUnsupported }
        _ = try command(["shell", "input", "keyevent", "3"], device, cancellation: cancellation)
        // Android KEYCODE_ALL_APPS = 284, added in API 28. A successful input
        // command is not proof that a particular launcher's drawer became visible.
        _ = try command(["shell", "input", "keyevent", "284"], device, cancellation: cancellation)
    }

    static func prefersSwipeForDrawer(homeResolution: String) -> Bool {
        let components = homeResolution.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("/") }
        return components == ["com.android.launcher3/com.bbk.launcher2.Launcher"]
    }

    func swipeUpForDrawer(for device: AndroidDevice, cancellation: ProcessCancellation?) throws {
        try ready(device, cancellation)
        _ = try command(["shell", "input", "keyevent", "3"], device, cancellation: cancellation)
        // wm size reports natural orientation; a transient screenshot supplies
        // current display coordinates without saving or exposing its pixels.
        for _ in 0..<10 { try checkCancellation(cancellation); Thread.sleep(forTimeInterval: 0.03) }
        try ready(device, cancellation)
        let frame = try command(["exec-out", "screencap", "-p"], device, timeout: 20,
                                limit: 67_108_864, cancellation: cancellation)
        guard Self.isCompletePNG(frame.stdout), let dimensions = Self.pngDimensions(frame.stdout) else {
            throw DeviceToolsError.invalidScreenSize
        }
        let x = dimensions.width / 2
        _ = try command(["shell", "input", "swipe", String(x), String(dimensions.height * 78 / 100),
                         String(x), String(dimensions.height * 22 / 100), "350"], device, cancellation: cancellation)
    }

    func healthCheck(for device: AndroidDevice, cancellation: ProcessCancellation?) throws -> DeviceHealthReport {
        try validate(device)
        try checkCancellation(cancellation)
        var items: [DeviceHealthItem] = []
        func item(_ id: String, _ severity: DeviceHealthSeverity, _ title: LocalizedMessage,
                  _ detail: LocalizedMessage, _ suggestion: LocalizedMessage? = nil) {
            items.append(DeviceHealthItem(id: id, severity: severity, titleMessage: title,
                                          detailMessage: detail, suggestionMessage: suggestion))
        }
        let localTools = paths.isUsable
        item("tools", localTools ? .success : .error, L10n.message("内置组件"),
             localTools ? L10n.message("ADB、scrcpy 和投屏服务文件可用。") : L10n.message("部分内置组件缺失。"),
             localTools ? nil : L10n.message("请重新下载并安装完整应用。"))
        let response = execute(["-s", device.serial, "get-state"], route(device), 6, 16_384, cancellation)
        try checkCancellation(cancellation)
        let connected = response.succeeded && String(decoding: response.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "device"
        item("connection", connected ? .success : .error, L10n.message("目标手机连接"),
             connected ? L10n.message("已确认所选手机处于已授权、就绪状态。") : L10n.message("所选手机未就绪，可能离线或尚未授权。"),
             connected ? nil : L10n.message("解锁手机并确认调试授权；无线连接请检查同一网络与配对状态。"))
        var version: String?, model: String?, size: String?
        if connected {
            version = try? text(["shell", "getprop", "ro.build.version.release"], device, cancellation)
            model = try? text(["shell", "getprop", "ro.product.model"], device, cancellation)
            let rawSize = try? text(["shell", "wm", "size"], device, cancellation)
            if let rawSize, let dimensions = Self.screenDimensions(rawSize) { size = "\(dimensions.width)×\(dimensions.height)" }
            item("android", version == nil ? .warning : .info, L10n.message("Android 版本与型号"),
                 L10n.message("Android %@ · %@", version ?? "—", model ?? "—"))
            item("screen", size == nil ? .warning : .info, L10n.message("手机显示尺寸"),
                 size.map { L10n.message("系统报告的屏幕尺寸：%@；实际投屏尺寸请查看会话信息。", $0) }
                    ?? L10n.message("暂时无法读取手机显示尺寸。"))
            let components = try? text(["shell", "ls", "/system/bin/screencap", "/system/bin/input"], device, cancellation)
            item("device-tools", components == nil ? .warning : .success, L10n.message("手机工具"),
                 components == nil ? L10n.message("无法确认手机的截图与输入工具。") : L10n.message("手机的截图与输入工具可用。"))
        }
        item("observability", .info, L10n.message("检测范围"), L10n.message("此检测不测量实时码率、帧率或温度，也不读取画面和原始日志。"),
             L10n.message("持续卡顿时优先尝试 USB、降低帧率或画质，并检查手机温度与其他占用网络的应用。"))
        try checkCancellation(cancellation)
        return DeviceHealthReport(checkedAt: Date(), isReady: connected, androidVersion: version,
                                  model: model, screenSize: size, items: items)
    }

    static func screenDimensions(_ value: String) -> (width: Int, height: Int)? {
        // Override size is the last valid wm-size line when present.
        let regex = try! NSRegularExpression(pattern: "(?:Physical|Override) size: ([0-9]{1,5})x([0-9]{1,5})")
        let ns = value as NSString
        guard let match = regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).last,
              let width = Int(ns.substring(with: match.range(at: 1))),
              let height = Int(ns.substring(with: match.range(at: 2))),
              (1...32768).contains(width), (1...32768).contains(height) else { return nil }
        return (width, height)
    }

    static func isCompletePNG(_ data: Data) -> Bool {
        guard data.count >= 32, data.starts(with: [137,80,78,71,13,10,26,10]),
              data.suffix(12) == Data([0,0,0,0,73,69,78,68,174,66,96,130]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32768, height <= 32768, width * height <= 80_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { return false }
        return true
    }

    private static func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private func validate(_ device: AndroidDevice) throws {
        guard !device.serial.isEmpty, device.serial.utf8.count <= 512,
              !device.serial.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw DeviceToolsError.invalidTarget }
    }
    private func route(_ device: AndroidDevice) -> [String: String] { ["ADB_SERVER_SOCKET": device.adbSocket ?? "tcp:5037"] }
    private func checkCancellation(_ token: ProcessCancellation?) throws {
        if token?.isCancelled == true { throw DeviceToolsError.cancelled }
    }
    private func ready(_ device: AndroidDevice, _ token: ProcessCancellation?) throws {
        guard device.state == .ready else { throw DeviceToolsError.deviceNotReady }
        let state = try text(["get-state"], device, token)
        guard state == "device" else { throw DeviceToolsError.deviceNotReady }
    }
    private func text(_ arguments: [String], _ device: AndroidDevice, _ token: ProcessCancellation?) throws -> String {
        let result = try command(arguments, device, cancellation: token)
        return String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func command(_ arguments: [String], _ device: AndroidDevice, timeout: TimeInterval = 8,
                         limit: Int = 262_144, cancellation: ProcessCancellation?, apkInstall: Bool = false) throws -> BinaryProcessResult {
        try validate(device)
        try checkCancellation(cancellation)
        let result = execute(["-s", device.serial] + arguments, route(device), timeout, limit, cancellation)
        try checkCancellation(cancellation)
        if result.status == -999 { throw DeviceToolsError.cancelled }
        if result.timedOut { throw DeviceToolsError.timedOut }
        if result.outputLimitExceeded { throw DeviceToolsError.outputTooLarge }
        guard result.succeeded else {
            if arguments.first == "install" || apkInstall {
                let failure = String(decoding: result.stdout + result.stderr, as: UTF8.self)
                if failure.contains("INSTALL_PARSE_FAILED") || failure.contains("INSTALL_FAILED_INVALID_APK") ||
                    failure.contains("Failed to parse APK file:") { throw DeviceToolsError.apkInvalid }
                if failure.contains("INSTALL_FAILED_ALREADY_EXISTS") || failure.contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") { throw DeviceToolsError.apkConflict }
                if failure.contains("INSTALL_FAILED_USER_RESTRICTED") || failure.contains("INSTALL_CANCELED_BY_USER") { throw DeviceToolsError.apkBlocked }
                if failure.contains("INSTALL_FAILED_NO_MATCHING_ABIS") || failure.contains("INSTALL_FAILED_OLDER_SDK") { throw DeviceToolsError.apkIncompatible }
            }
            throw DeviceToolsError.commandFailed
        }
        return result
    }
}
