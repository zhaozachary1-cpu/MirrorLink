import Foundation

struct ScrcpyCommand {
    let paths: ToolPaths

    func arguments(for device: AndroidDevice) -> [String] {
        [
            "-s", device.serial,
            "--window-title=\(windowTitle(for: device))"
        ]
    }

    func windowTitle(for device: AndroidDevice) -> String {
        "镜连 · \(device.logLabel)"
    }

    func environment(for device: AndroidDevice) -> [String: String] {
        [
            "ADB": paths.adb.path,
            "SCRCPY_SERVER_PATH": paths.server.path,
            "SCRCPY_ICON_DIR": paths.server.deletingLastPathComponent().path,
            "ANDROID_SERIAL": device.serial,
            "ADB_SERVER_SOCKET": device.adbSocket ?? "tcp:5037"
        ]
    }
}
