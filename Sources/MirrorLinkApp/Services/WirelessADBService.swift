import Foundation

struct WirelessDiscoveryResult: Sendable {
    let services: [WirelessService]
    let warningMessage: LocalizedMessage?
    var warning: String? { warningMessage?.resolved }

    init(services: [WirelessService], warningMessage: LocalizedMessage?) {
        self.services = services
        self.warningMessage = warningMessage
    }

    // Preserve callers that supply a diagnostic which must remain verbatim.
    init(services: [WirelessService], warning: String?) {
        self.init(services: services, warningMessage: warning.map(LocalizedMessage.verbatim))
    }
}

/// Mutating operations stay on their configured server. Never reset a shared
/// daemon, enable tcpip/5555, scan IP ranges, or disconnect another transport.
struct WirelessADBService: Sendable {
    typealias Executor = @Sendable ([String], String?, TimeInterval) -> ProcessResult
    typealias CancellableExecutor = @Sendable ([String], String?, TimeInterval, ProcessCancellation?) -> ProcessResult
    typealias NativeDiscovery = @Sendable (ProcessCancellation?) -> [WirelessService]
    typealias NetworkReadiness = @Sendable (WirelessEndpoint, TimeInterval, ProcessCancellation?) -> Bool
    private let run: CancellableExecutor
    private let nativeDiscovery: NativeDiscovery
    private let networkReadiness: NetworkReadiness
    private let adbSocket: String?

    init(paths: ToolPaths, execute: Executor? = nil, cancellableExecute: CancellableExecutor? = nil,
         nativeDiscovery: NativeDiscovery? = nil, networkReadiness: NetworkReadiness? = nil,
         adbSocket: String? = nil, prepareBackend: (@Sendable () -> Bool)? = nil) {
        self.adbSocket = adbSocket
        if let networkReadiness { self.networkReadiness = networkReadiness }
        else if execute == nil && cancellableExecute == nil {
            self.networkReadiness = { LocalNetworkReadiness.wait(for: $0, timeout: $1, cancellation: $2) }
        } else { self.networkReadiness = { _, _, token in token?.isCancelled != true } }
        // Injected ADB tests must never silently browse the real LAN.
        if let nativeDiscovery { self.nativeDiscovery = nativeDiscovery }
        else if execute == nil && cancellableExecute == nil {
            self.nativeDiscovery = { BonjourWirelessDiscovery.discover(cancellation: $0) }
        } else { self.nativeDiscovery = { _ in [] } }
        self.run = cancellableExecute ?? { arguments, input, timeout, cancellation in
            if let execute { return execute(arguments, input, timeout) }
            guard prepareBackend?() != false, cancellation?.isCancelled != true else {
                return ProcessResult(status: -1, stdout: "", stderr: "cannot connect to daemon", timedOut: false)
            }
            return ProcessRunner.run(
                executablePath: paths.adb.path,
                arguments: arguments,
                environmentOverrides: ["ADB_SERVER_SOCKET": adbSocket ?? "tcp:5037"],
                standardInput: input,
                timeout: timeout,
                cancellation: cancellation
            )
        }
    }

    func discover(cancellation: ProcessCancellation? = nil) -> WirelessDiscoveryResult {
        let native = nativeDiscovery(cancellation)
        guard cancellation?.isCancelled != true else {
            return WirelessDiscoveryResult(services: [], warningMessage: nil)
        }
        let result = execute(["mdns", "services"], nil, 6, cancellation)
        guard cancellation?.isCancelled != true else {
            return WirelessDiscoveryResult(services: [], warningMessage: nil)
        }
        let services = WirelessService.merging(native + (result.succeeded ? ADBMDNSParser.parse(result.stdout) : []))
        if !services.isEmpty { return WirelessDiscoveryResult(services: services, warningMessage: nil) }
        guard result.succeeded else {
            return WirelessDiscoveryResult(services: [], warningMessage: L10n.message("无法查找手机，请检查本地网络权限或手动连接。"))
        }
        return WirelessDiscoveryResult(services: services, warningMessage: services.isEmpty
            ? L10n.message("未找到手机，请连接同一 Wi-Fi 并开启“无线调试”。") : nil)
    }

    func pair(endpoint: WirelessEndpoint, code: String, cancellation: ProcessCancellation? = nil) -> Result<Void, WirelessConnectionError> {
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return .failure(.invalidPairingCode)
        }
        guard networkReadiness(endpoint, 15, cancellation) else { return .failure(networkFailure) }
        // Do not put the code in argv (visible to other processes) or logs.
        let result = execute(["pair", endpoint.address], code + "\n", 25, cancellation)
        guard result.succeeded, result.stdout.contains("Successfully paired to ") else {
            return .failure(failure(result, pairing: true))
        }
        return .success(())
    }

    func pairQR(endpoint: WirelessEndpoint, session: WirelessQRSession,
                cancellation: ProcessCancellation? = nil) -> Result<WirelessPairingIdentity, WirelessConnectionError> {
        let remaining = session.expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return .failure(.localizedFailure(L10n.message("二维码已过期，请刷新二维码。"))) }
        guard networkReadiness(endpoint, min(15, remaining), cancellation) else { return .failure(networkFailure) }
        // A privacy decision may arrive after the first helper failed. Retry
        // only a transport denial, on the same endpoint and live QR credential.
        let pairingBudget = session.expiresAt.timeIntervalSinceNow
        guard pairingBudget > 0 else { return .failure(.localizedFailure(L10n.message("二维码已过期，请刷新二维码。"))) }
        var result = execute(["pair", endpoint.address], session.password + "\n", min(25, pairingBudget), cancellation)
        if isNetworkDenied(result), cancellation?.isCancelled != true, session.expiresAt.timeIntervalSinceNow > 1,
           networkReadiness(endpoint, min(5, session.expiresAt.timeIntervalSinceNow), cancellation) {
            let retryBudget = session.expiresAt.timeIntervalSinceNow
            guard retryBudget > 0 else { return .failure(.localizedFailure(L10n.message("二维码已过期，请刷新二维码。"))) }
            result = execute(["pair", endpoint.address], session.password + "\n", min(25, retryBudget), cancellation)
        }
        guard session.expiresAt > Date() else {
            return .failure(.localizedFailure(L10n.message("二维码已过期；已配对可直接连接，否则请刷新二维码。")))
        }
        guard result.succeeded, let identity = WirelessPairingIdentity(output: result.stdout, endpoint: endpoint) else {
            // Never surface tool output: it can echo the QR credential.
            if isNetworkDenied(result) { return .failure(networkFailure) }
            let diagnostic = (result.stdout + result.stderr).lowercased()
            if diagnostic.contains("connection refused") {
                return .failure(.localizedFailure(L10n.message("手机扫码已关闭，请重新打开后扫码。")))
            }
            if diagnostic.contains("authenticate") || diagnostic.contains("authentication") || diagnostic.contains("wrong password") {
                return .failure(.localizedFailure(L10n.message("扫码授权已失效，请刷新二维码。")))
            }
            if diagnostic.contains("cannot connect to daemon") || diagnostic.contains("failed to start daemon") {
                return .failure(.localizedFailure(L10n.message("连接服务不可用，请重启镜连。")))
            }
            return .failure(.localizedFailure(result.timedOut
                ? L10n.message("扫码超时，请检查网络后刷新二维码。")
                : L10n.message("扫码未完成，请刷新二维码后重新扫描。")))
        }
        return .success(identity)
    }

    func connect(endpoint: WirelessEndpoint, expectedIdentity: WirelessPairingIdentity? = nil,
                 cancellation: ProcessCancellation? = nil) -> Result<AndroidDevice, WirelessConnectionError> {
        guard networkReadiness(endpoint, 15, cancellation) else { return .failure(networkFailure) }
        var result = execute(["connect", endpoint.address], nil, 15, cancellation)
        if isNetworkDenied(result), cancellation?.isCancelled != true,
           networkReadiness(endpoint, 5, cancellation) {
            // A newly installed ad-hoc helper can receive a delayed network
            // decision after the native app is allowed. One bounded retry on
            // this exact endpoint avoids requiring another manual click.
            let retryAt = Date().addingTimeInterval(1)
            while Date() < retryAt, cancellation?.isCancelled != true {
                Thread.sleep(forTimeInterval: 0.05)
            }
            result = execute(["connect", endpoint.address], nil, 15, cancellation)
        }
        let hasAcknowledgement = result.stdout.split(whereSeparator: \.isNewline).contains {
            $0.hasPrefix("connected to ") || $0.hasPrefix("already connected to ")
        }
        // adb can exit 0 even when the text says connection failed.
        guard result.succeeded, hasAcknowledgement else { return .failure(failure(result, pairing: false)) }

        let listing = execute(["devices", "-l"], nil, 6, cancellation)
        guard listing.succeeded else { return .failure(failure(listing, pairing: false)) }
        let devices = ADBDeviceParser.parse(listing.stdout, adbSocket: adbSocket)
        var match = devices.first { (try? WirelessEndpoint($0.serial)) == endpoint }
        if match == nil {
            // ADB may already have auto-connected this endpoint under its mDNS
            // name. Resolve only this address, never pick the first ready phone.
            let aliases = discover(cancellation: cancellation).services.filter { $0.kind == .connection && $0.endpoint == endpoint }.map(\.adbSerial)
            match = devices.first { device in
                aliases.contains(device.serial) || aliases.contains(where: {
                    device.serial == $0 + "." || device.serial == $0 + ".local" || device.serial == $0 + ".local."
                })
            }
        }
        guard var device = match, device.isWireless else {
            return .failure(.localizedFailure(L10n.message("未确认目标手机，请核对地址后重试。")))
        }
        let state = execute(["-s", device.serial, "get-state"], nil, 5, cancellation)
        guard device.state == .ready, state.succeeded,
              state.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
            return .failure(.localizedFailure(L10n.message("手机未就绪，请解锁并开启“无线调试”。")))
        }
        device.hardwareSerial = ADBDeviceIdentity.hardwareSerial(from:
            execute(["-s", device.serial, "shell", "getprop", "ro.serialno"], nil, 3, cancellation))
        if let expectedIdentity {
            let identity = execute(["-s", device.serial, "shell", "getprop", "persist.adb.wifi.guid"], nil, 3, cancellation)
            let reportedGUID = identity.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            var verified = identity.succeeded && reportedGUID == expectedIdentity.guid
            if identity.succeeded, reportedGUID.isEmpty,
               expectedIdentity.containsHardwareSerial(device.hardwareSerial) {
                // Do not turn an unreadable OEM property into a false mismatch.
                // Bind the paired GUID to the actual shell hardware identity
                // and re-resolve exactly one current service on this endpoint.
                let matches = discover(cancellation: cancellation).services.filter(expectedIdentity.matches)
                verified = matches.count == 1 && matches[0].endpoint == endpoint
            }
            guard verified else {
                return .failure(.localizedFailure(L10n.message("手机身份不匹配，请重新扫码。")))
            }
        }
        let metadata = execute(["-s", device.serial, "shell", AndroidDevice.brandQuery], nil, 2, cancellation)
        if metadata.succeeded { device.brand = AndroidDevice.brand(fromProperties: metadata.stdout) }
        guard cancellation?.isCancelled != true else { return .failure(.localizedFailure(L10n.message("连接已取消。"))) }
        return .success(device)
    }

    private func execute(_ arguments: [String], _ input: String?, _ timeout: TimeInterval,
                         _ cancellation: ProcessCancellation?) -> ProcessResult {
        guard cancellation?.isCancelled != true else {
            return ProcessResult(status: -999, stdout: "", stderr: "", timedOut: false)
        }
        return run(arguments, input, timeout, cancellation)
    }

    private func failure(_ result: ProcessResult, pairing: Bool) -> WirelessConnectionError {
        // Never return raw pair output: tool errors could echo the secret input.
        if result.timedOut {
            return .localizedFailure(pairing
                ? L10n.message("配对超时，请检查 Wi-Fi 和本地网络权限。")
                : L10n.message("连接超时，请检查 Wi-Fi 和本地网络权限。"))
        }
        let diagnostic = (result.stdout + result.stderr).lowercased()
        if isNetworkDenied(result) { return networkFailure }
        if !pairing && (diagnostic.contains("authenticate") || diagnostic.contains("authentication")) {
            return .localizedFailure(L10n.message("连接授权已失效，请重新扫码。"))
        }
        return .localizedFailure(pairing
            ? L10n.message("配对失败，请核对地址和配对码后重试。")
            : L10n.message("连接失败，请重新开启手机的无线调试。"))
    }

    private var networkFailure: WirelessConnectionError {
        .localizedFailure(L10n.message("无法访问手机，请允许镜连访问本地网络。"))
    }

    private func isNetworkDenied(_ result: ProcessResult) -> Bool {
        let text = (result.stdout + result.stderr).lowercased()
        return ["no route to host", "network is unreachable", "operation not permitted", "permission denied"].contains { text.contains($0) }
    }
}
