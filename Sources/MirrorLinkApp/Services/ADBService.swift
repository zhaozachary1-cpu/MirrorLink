import Foundation

struct ADBSnapshot: Sendable {
    let devices: [AndroidDevice]
    let diagnostics: [String]
    /// UI rows may merge one phone's transports; recovery must still see every
    /// independently authenticated route rather than inheriting that UI choice.
    let rawRoutes: [AndroidDevice]

    init(devices: [AndroidDevice], diagnostics: [String], rawRoutes: [AndroidDevice]? = nil) {
        self.devices = devices
        self.diagnostics = diagnostics
        self.rawRoutes = rawRoutes ?? devices
    }
}

struct ADBService: Sendable {
    let paths: ToolPaths

    func snapshot(additionalSockets: [String] = []) -> ADBSnapshot {
        var allDevices: [AndroidDevice] = []
        var rawRoutes: [AndroidDevice] = []
        var diagnostics: [String] = []

        let sockets = [String?(nil), "tcp:127.0.0.1:5038"] + additionalSockets.map(Optional.some)
        for socket in sockets {
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
                    if device.state == .ready {
                        let metadata = ProcessRunner.run(executablePath: paths.adb.path,
                            arguments: ["-s", device.serial, "shell", AndroidDevice.brandQuery],
                            environmentOverrides: overrides, timeout: 2)
                        if metadata.succeeded { device.brand = AndroidDevice.brand(fromProperties: metadata.stdout) }
                    }
                    if device.isWireless && device.state == .ready {
                        device.hardwareSerial = ADBDeviceIdentity.hardwareSerial(from: ProcessRunner.run(
                            executablePath: paths.adb.path,
                            arguments: ["-s", device.serial, "shell", "getprop", "ro.serialno"],
                            environmentOverrides: overrides,
                            timeout: 2
                        ))
                    }
                    rawRoutes.append(device)
                    if let existing = allDevices.firstIndex(where: { $0.id == device.id }) {
                        allDevices[existing] = ADBDeviceIdentity.preferred(allDevices[existing], device)
                    } else {
                        allDevices.append(device)
                    }
                }
            } else {
                let error = result.timedOut ? L10n.tr("扫描超时，请检查 USB / Wi-Fi 连接后刷新。") : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                // An absent optional 5038 daemon is normal. Never hide a primary-daemon failure.
                if !error.isEmpty && (socket == nil || !error.contains("cannot connect")) {
                    let label = socket == nil ? "ADB 5037" : (socket == "tcp:127.0.0.1:5038" ? "ADB 5038" : "MirrorLink Wireless")
                    diagnostics.append("\(label): \(error)")
                }
            }
        }

        allDevices.sort {
            if $0.state == $1.state { return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return stateRank($0.state) < stateRank($1.state)
        }
        return ADBSnapshot(devices: allDevices, diagnostics: diagnostics, rawRoutes: rawRoutes)
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
