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
        precondition(command.arguments(for: device) == ["-s", "ABC123", "--window-title=镜连 · Pixel 6 · ABC123", "--no-terminal-title"], "scrcpy arguments")
        precondition(command.environment(for: device)["ADB_SERVER_SOCKET"] == "tcp:127.0.0.1:5038", "alternate ADB socket")

        let secondDevice = AndroidDevice(serial: "DEF456789", model: "Pixel_8", product: "shiba", transport: "USB", state: .ready, adbSocket: "tcp:127.0.0.1:5037")
        precondition(command.arguments(for: device).prefix(2) == ["-s", "ABC123"], "first device serial pinning")
        precondition(command.arguments(for: secondDevice).prefix(2) == ["-s", "DEF456789"], "second device serial pinning")
        precondition(command.windowTitle(for: device) != command.windowTitle(for: secondDevice), "unique scrcpy windows")
        print("MirrorLink core checks passed")
    }
}
