import Foundation

struct ADBSnapshot: Sendable {
    let devices: [AndroidDevice]
    let diagnostics: [String]
}

struct ADBService: Sendable {
    let paths: ToolPaths

    func snapshot() -> ADBSnapshot {
        var allDevices: [AndroidDevice] = []
        var diagnostics: [String] = []

        for socket in [String?(nil), "tcp:127.0.0.1:5038"] {
            // A local socket lets ADB start its default daemon when necessary.
            // The optional 5038 endpoint is connect-only; never start/kill it.
            let overrides = ["ADB_SERVER_SOCKET": socket ?? "tcp:5037"]

            let result = ProcessRunner.run(
                executablePath: paths.adb.path,
                arguments: ["devices", "-l"],
                environmentOverrides: overrides,
                timeout: 6
            )

            if result.succeeded {
                let devices = ADBDeviceParser.parse(result.stdout, adbSocket: socket)
                for var device in devices {
                    if device.isWireless && device.state == .ready {
                        device.hardwareSerial = ADBDeviceIdentity.hardwareSerial(from: ProcessRunner.run(
                            executablePath: paths.adb.path,
                            arguments: ["-s", device.serial, "shell", "getprop", "ro.serialno"],
                            environmentOverrides: overrides,
                            timeout: 2
                        ))
                    }
                    if let existing = allDevices.firstIndex(where: { $0.id == device.id }) {
                        allDevices[existing] = ADBDeviceIdentity.preferred(allDevices[existing], device)
                    } else {
                        allDevices.append(device)
                    }
                }
            } else {
                let error = result.timedOut ? "扫描超时，请检查 USB / Wi-Fi 连接后刷新。" : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                // An absent optional 5038 daemon is normal. Never hide a primary-daemon failure.
                if !error.isEmpty && (socket == nil || !error.contains("cannot connect")) {
                    diagnostics.append("\(socket == nil ? "ADB 5037" : "ADB 5038"): \(error)")
                }
            }
        }

        allDevices.sort {
            if $0.state == $1.state { return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return stateRank($0.state) < stateRank($1.state)
        }
        return ADBSnapshot(devices: allDevices, diagnostics: diagnostics)
    }

    private func stateRank(_ state: DeviceConnectionState) -> Int {
        switch state {
        case .ready: return 0
        case .unauthorized: return 1
        case .offline: return 2
        case .unknown: return 3
        }
    }
}
