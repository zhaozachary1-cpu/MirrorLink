import Foundation

@main
struct MirrorLinkCoreChecks {
    static func main() {
        let output = """
        List of devices attached
        ABC123\tdevice usb:1-1 product:oriole model:Pixel_6 device:oriole transport_id:1
        DEF456\tunauthorized usb:1-2 product:foo model:Unknown device:foo transport_id:2
        """
        let devices = ADBDeviceParser.parse(output, adbSocket: nil)
        precondition(devices.count == 2, "ADB parser count")
        precondition(devices[0].state == .ready, "ADB ready state")
        precondition(devices[0].displayName == "Pixel 6", "ADB model normalization")
        precondition(devices[1].state == .unauthorized, "ADB authorization state")

        let root = URL(fileURLWithPath: "/tmp/mirrorlink/tools")
        let paths = ToolPaths(root: root, adb: root.appendingPathComponent("adb"), scrcpy: root.appendingPathComponent("scrcpy"), server: root.appendingPathComponent("scrcpy-server"))
        let device = AndroidDevice(serial: "ABC123", model: "Pixel_6", product: "oriole", transport: "USB", state: .ready, adbSocket: "tcp:127.0.0.1:5038")
        let command = ScrcpyCommand(paths: paths)
        let defaultArguments = command.arguments(for: device)
        precondition(Array(defaultArguments.prefix(4)) == ["-s", "ABC123", "--window-title=镜连 · Pixel 6 · ABC123", "--no-terminal-title"], "scrcpy device and log arguments")
        precondition(defaultArguments.contains("--video-bit-rate=24M") && defaultArguments.contains("--max-size=0") && defaultArguments.contains("--max-fps=30"), "default native clarity is explicit")
        precondition(command.environment(for: device)["ADB_SERVER_SOCKET"] == "tcp:127.0.0.1:5038", "alternate ADB socket")

        let secondDevice = AndroidDevice(serial: "DEF456789", model: "Pixel_8", product: "shiba", transport: "USB", state: .ready, adbSocket: "tcp:127.0.0.1:5037")
        precondition(command.arguments(for: device).prefix(2) == ["-s", "ABC123"], "first device serial pinning")
        precondition(command.arguments(for: secondDevice).prefix(2) == ["-s", "DEF456789"], "second device serial pinning")
        precondition(command.windowTitle(for: device) != command.windowTitle(for: secondDevice), "unique scrcpy windows")

        var wireless = AndroidDevice(serial: "192.168.1.8:39847", model: device.model, product: device.product, transport: "Wi-Fi", state: .ready, adbSocket: device.adbSocket)
        wireless.hardwareSerial = device.serial
        wireless.sessionIdentity = device.id
        for (profile, size, bitRate, fps) in [
            (MirrorQualityProfile.nativeClarity, 0, 24, 30),
            (.nativeSmooth, 0, 24, 60),
            (.compatibility, 1920, 12, 30)
        ] {
            precondition(profile.maxSize == size && profile.videoBitRateMbps == bitRate && profile.maxFPS == fps, "quality profile values")
            for target in [device, wireless] {
                let arguments = command.arguments(for: target, quality: profile)
                let expectedVideo = ["--video-codec=h264", "--video-bit-rate=\(bitRate)M", "--max-size=\(size)", "--max-fps=\(fps)", "--video-buffer=\(target.isWireless ? 80 : 0)", "--no-downsize-on-error"]
                for flag in expectedVideo {
                    precondition(arguments.filter { $0 == flag }.count == 1, "video argument occurs exactly once: \(flag)")
                }
                for prefix in ["--video-codec=", "--video-bit-rate=", "--max-size=", "--max-fps=", "--video-buffer="] {
                    precondition(arguments.filter { $0.hasPrefix(prefix) }.count == 1, "conflicting overrides are absent: \(prefix)")
                }
                precondition(Array(arguments.prefix(2)) == ["-s", target.serial], "quality keeps the exact authorized transport")
                precondition(command.environment(for: target)["ANDROID_SERIAL"] == target.serial, "quality keeps environment route")
            }
            precondition(profile.videoBufferMilliseconds(isWireless: true) == 80 && profile.videoBufferMilliseconds(isWireless: false) == 0, "transport-specific bounded buffering")
        }
        precondition(MirrorQualityProfile.restored(from: nil) == .nativeClarity, "missing preference defaults to native clarity")
        precondition(MirrorQualityProfile.restored(from: "invalid-future-profile") == .nativeClarity, "unknown preference defaults safely")
        precondition(MirrorQualityProfile.restored(from: MirrorQualityProfile.nativeSmooth.rawValue) == .nativeSmooth, "known preference restores")

        let native = VideoResolution.parse(logLine: "INFO: Texture: 1080x2400")!
        let rotated = VideoResolution.parse(logLine: "  INFO:   Texture:   2400x1080  ")!
        let reduced = VideoResolution.parse(logLine: "INFO: Texture: 720x1600")!
        precondition(native.pixelCount == 2_592_000 && !native.displayText.isEmpty, "resolution metadata reflects video dimensions")
        precondition(!rotated.isSmaller(than: native) && !native.isSmaller(than: rotated), "rotation is not resolution loss")
        precondition(reduced.isSmaller(than: native) && !native.isSmaller(than: reduced), "smaller dimensions are detected")
        for line in ["ERROR: Texture: 1080x2400", "untrusted INFO: Texture: 1080x2400", "INFO: Texture: 0x2400", "INFO: Texture: -1x2400", "INFO: Texture: 1080x0", "INFO: Texture: 16385x2400", "INFO: Texture: 1080x2400 garbage", "INFO: Texture: 1080x", "INFO: Texture: 1e3x2400"] {
            precondition(VideoResolution.parse(logLine: line) == nil, "reject malformed video dimensions: \(line)")
        }
        print("MirrorLink core checks passed")
    }
}
