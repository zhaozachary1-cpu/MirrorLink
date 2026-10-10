import Foundation

struct ScrcpyCommand {
    let paths: ToolPaths

    func arguments(for device: AndroidDevice, quality: MirrorQualityProfile = .nativeClarity) -> [String] {
        [
            "-s", device.serial,
            "--window-title=\(windowTitle(for: device))",
            // stdout is a private log PTY, not an interactive terminal.
            "--no-terminal-title",
            "--video-codec=h264",
            "--video-bit-rate=\(quality.videoBitRateMbps)M",
            "--max-size=\(quality.maxSize)",
            "--max-fps=\(quality.maxFPS)",
            "--video-buffer=\(quality.videoBufferMilliseconds(isWireless: device.isWireless))",
            // Quality reduction is a user's explicit choice, never a hidden
            // resolution fallback after an encoder initialization failure.
            "--no-downsize-on-error"
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
