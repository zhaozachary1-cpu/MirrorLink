import Foundation

struct ScrcpyCommand {
    let paths: ToolPaths

    func arguments(for device: AndroidDevice, quality: MirrorQualityProfile = .nativeClarity,
                   preferences: DevicePreferences = DevicePreferences(), placement: MirrorWindowPlacement? = nil,
                   recordingURL: URL? = nil) -> [String] {
        var arguments = [
            "-s", device.serial,
            "--window-title=\(windowTitle(for: device, preferences: preferences))",
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
        if !preferences.audioEnabled { arguments.append("--no-audio") }
        if preferences.presentationMode { arguments += ["--no-control", "--no-clipboard-autosync"] }
        if preferences.alwaysOnTop { arguments.append("--always-on-top") }
        if preferences.fullscreen { arguments.append("--fullscreen") }
        if let placement, !preferences.fullscreen { arguments += placement.arguments }
        if let recordingURL {
            arguments += ["--record=\(recordingURL.path)", "--record-format=mp4"]
            // MP4 exports use AAC for native player compatibility. Ordinary
            // mirroring retains scrcpy's default codec; silent captures do not
            // initialize an unnecessary audio encoder.
            if preferences.audioEnabled { arguments.append("--audio-codec=aac") }
        }
        return arguments
    }

    func windowTitle(for device: AndroidDevice, preferences: DevicePreferences = DevicePreferences()) -> String {
        let nickname = preferences.normalized.nickname
        let name = nickname.isEmpty ? device.displayName : nickname
        let label = preferences.presentationMode ? (name == device.serial ? L10n.tr("Android 手机") : name)
            : (nickname.isEmpty ? device.logLabel : "\(nickname) · \(device.serial)")
        return L10n.tr("镜连 · %@", label)
    }

    func environment(for device: AndroidDevice) -> [String: String] {
        [
            "ADB": paths.adb.path,
            "ADB_MDNS": "0",
            "SCRCPY_SERVER_PATH": paths.server.path,
            "SCRCPY_ICON_DIR": paths.server.deletingLastPathComponent().path,
            "ANDROID_SERIAL": device.serial,
            "ADB_SERVER_SOCKET": device.adbSocket ?? "tcp:5037"
        ]
    }
}
