import Foundation

struct WirelessDiscoveryResult: Sendable {
    let services: [WirelessService]
    let warning: String?
}

/// Mutating connection operations use only the default ADB daemon. Never reset
/// a daemon, enable tcpip/5555, scan IP ranges, or disconnect another transport.
struct WirelessADBService: Sendable {
    typealias Executor = @Sendable ([String], String?, TimeInterval) -> ProcessResult
    private let execute: Executor

    init(paths: ToolPaths, execute: Executor? = nil) {
        self.execute = execute ?? { arguments, input, timeout in
            ProcessRunner.run(
                executablePath: paths.adb.path,
                arguments: arguments,
                environmentOverrides: ["ADB_SERVER_SOCKET": "tcp:5037"],
                standardInput: input,
                timeout: timeout
            )
        }
    }

    func discover() -> WirelessDiscoveryResult {
        let result = execute(["mdns", "services"], nil, 6)
        guard result.succeeded else {
            return WirelessDiscoveryResult(services: [], warning: "暂时无法发现手机。可手动填写地址；请检查 macOS 的本地网络权限、手机无线调试，以及 Wi-Fi 是否允许设备互访。")
        }
        let services = ADBMDNSParser.parse(result.stdout)
        return WirelessDiscoveryResult(services: services, warning: services.isEmpty
            ? "未发现服务。首次配对请保持手机的“使用配对码配对设备”窗口打开；也可直接手动填写地址。" : nil)
    }

    func pair(endpoint: WirelessEndpoint, code: String) -> Result<Void, WirelessConnectionError> {
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return .failure(.invalidPairingCode)
        }
        // Do not put the code in argv (visible to other processes) or logs.
        let result = execute(["pair", endpoint.address], code + "\n", 25)
        guard result.succeeded, result.stdout.contains("Successfully paired to ") else {
            return .failure(failure(result, pairing: true))
        }
        return .success(())
    }

    func connect(endpoint: WirelessEndpoint) -> Result<AndroidDevice, WirelessConnectionError> {
        let result = execute(["connect", endpoint.address], nil, 15)
        let hasAcknowledgement = result.stdout.split(whereSeparator: \.isNewline).contains {
            $0.hasPrefix("connected to ") || $0.hasPrefix("already connected to ")
        }
        // adb can exit 0 even when the text says connection failed.
        guard result.succeeded, hasAcknowledgement else { return .failure(failure(result, pairing: false)) }

        let listing = execute(["devices", "-l"], nil, 6)
        guard listing.succeeded else { return .failure(failure(listing, pairing: false)) }
        let devices = ADBDeviceParser.parse(listing.stdout, adbSocket: nil)
        var match = devices.first { (try? WirelessEndpoint($0.serial)) == endpoint }
        if match == nil {
            // ADB may already have auto-connected this endpoint under its mDNS
            // name. Resolve only this address, never pick the first ready phone.
            let aliases = discover().services.filter { $0.kind == .connection && $0.endpoint == endpoint }.map(\.adbSerial)
            match = devices.first { device in
                aliases.contains(device.serial) || aliases.contains(where: {
                    device.serial == $0 + "." || device.serial == $0 + ".local" || device.serial == $0 + ".local."
                })
            }
        }
        guard var device = match, device.isWireless else {
            return .failure(.failed("ADB 返回已连接，但尚未确认这台手机。请检查地址并重试；不会自动选择其他手机投屏。"))
        }
        let state = execute(["-s", device.serial, "get-state"], nil, 5)
        guard device.state == .ready, state.succeeded,
              state.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
            return .failure(.failed("手机尚未就绪。请解锁手机，确认无线调试已开启；若授权已失效，请重新配对。"))
        }
        device.hardwareSerial = ADBDeviceIdentity.hardwareSerial(from:
            execute(["-s", device.serial, "shell", "getprop", "ro.serialno"], nil, 3))
        return .success(device)
    }

    private func failure(_ result: ProcessResult, pairing: Bool) -> WirelessConnectionError {
        // Never return raw pair output: tool errors could echo the secret input.
        if result.timedOut {
            return .failed("\(pairing ? "配对" : "连接")超时。请确认手机和 Mac 在同一 Wi-Fi，允许镜连访问本地网络，并检查访客网络、VPN 或路由器的设备隔离设置。")
        }
        let diagnostic = (result.stdout + result.stderr).lowercased()
        if !pairing && (diagnostic.contains("authenticate") || diagnostic.contains("authentication")) {
            return .failed("无线调试授权无效。请先在“首次配对”中使用手机新生成的配对码重新配对。")
        }
        return .failed(pairing
            ? "配对未成功。请保持手机配对码窗口打开，重新核对其中的 IP、配对端口和 6 位配对码；配对码过期后需重新生成。"
            : "连接未成功。请填写“无线调试”主页面的 IP 和连接端口（不是配对码窗口的端口）；重新开启无线调试或切换网络后，端口可能变化。")
    }
}
