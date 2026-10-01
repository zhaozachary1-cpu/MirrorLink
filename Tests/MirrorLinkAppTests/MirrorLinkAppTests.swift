import XCTest
@testable import MirrorLinkApp

final class MirrorLinkAppTests: XCTestCase {
    func testParsesReadyUnauthorizedAndOfflineDevices() {
        let output = """
        List of devices attached
        ABC123\tdevice usb:1-1 product:oriole model:Pixel_6 device:oriole transport_id:1
        DEF456\tunauthorized usb:1-2 product:foo model:Unknown device:foo transport_id:2
        GHI789\toffline usb:1-3 product:bar model:Offline device:bar transport_id:3
        """

        let devices = ADBDeviceParser.parse(output, adbSocket: nil)

        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].serial, "ABC123")
        XCTAssertEqual(devices[0].state, .ready)
        XCTAssertEqual(devices[0].displayName, "Pixel 6")
        XCTAssertEqual(devices[1].state, .unauthorized)
        XCTAssertEqual(devices[2].state, .offline)
        XCTAssertEqual(devices[0].transport, "USB")
    }

    func testUSBDeviceRetainsRouteSeparatelyFromIdentity() {
        let devices = ADBDeviceParser.parse(
            "SERIAL\tdevice product:p model:Phone device:p transport_id:7",
            adbSocket: "tcp:127.0.0.1:5038"
        )

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "SERIAL")
        XCTAssertEqual(devices.first?.adbSocket, "tcp:127.0.0.1:5038")
        XCTAssertEqual(devices.first?.transport, "USB")
    }

    func testScrcpyCommandUsesBundledRuntimeAndSelectedSocket() {
        let root = URL(fileURLWithPath: "/tmp/mirrorlink/tools")
        let paths = ToolPaths(
            root: root,
            adb: root.appendingPathComponent("adb"),
            scrcpy: root.appendingPathComponent("scrcpy"),
            server: root.appendingPathComponent("scrcpy-server")
        )
        let device = AndroidDevice(
            serial: "ABC123",
            model: "Pixel_6",
            product: "oriole",
            transport: "USB",
            state: .ready,
            adbSocket: "tcp:127.0.0.1:5038"
        )

        let command = ScrcpyCommand(paths: paths)

        XCTAssertEqual(command.arguments(for: device), ["-s", "ABC123", "--window-title=镜连 · Pixel 6 · ABC123"])
        XCTAssertEqual(command.environment(for: device)["ADB"], "/tmp/mirrorlink/tools/adb")
        XCTAssertEqual(command.environment(for: device)["SCRCPY_SERVER_PATH"], "/tmp/mirrorlink/tools/scrcpy-server")
        XCTAssertEqual(command.environment(for: device)["ADB_SERVER_SOCKET"], "tcp:127.0.0.1:5038")
    }

    func testScrcpyCommandKeepsTwoDevicesOnDistinctWindowsAndSockets() {
        let root = URL(fileURLWithPath: "/tmp/mirrorlink/tools")
        let paths = ToolPaths(
            root: root,
            adb: root.appendingPathComponent("adb"),
            scrcpy: root.appendingPathComponent("scrcpy"),
            server: root.appendingPathComponent("scrcpy-server")
        )
        let first = AndroidDevice(
            serial: "FIRST123456",
            model: "Pixel_6",
            product: "oriole",
            transport: "USB",
            state: .ready,
            adbSocket: "tcp:127.0.0.1:5037"
        )
        let second = AndroidDevice(
            serial: "SECOND987654",
            model: "Pixel_8",
            product: "shiba",
            transport: "USB",
            state: .ready,
            adbSocket: "tcp:127.0.0.1:5038"
        )

        let command = ScrcpyCommand(paths: paths)

        XCTAssertNotEqual(command.windowTitle(for: first), command.windowTitle(for: second))
        XCTAssertEqual(command.arguments(for: first).prefix(2), ["-s", "FIRST123456"])
        XCTAssertEqual(command.arguments(for: second).prefix(2), ["-s", "SECOND987654"])
        XCTAssertEqual(command.environment(for: first)["ADB_SERVER_SOCKET"], "tcp:127.0.0.1:5037")
        XCTAssertEqual(command.environment(for: second)["ADB_SERVER_SOCKET"], "tcp:127.0.0.1:5038")
    }

    func testAndroidDeviceIdentityRemainsStableAcrossAdbDaemons() {
        let first = AndroidDevice(
            serial: "SAME_SERIAL",
            model: "Pixel_6",
            product: "oriole",
            transport: "USB",
            state: .ready,
            adbSocket: "tcp:127.0.0.1:5037"
        )
        let second = AndroidDevice(
            serial: "SAME_SERIAL",
            model: "Pixel_6",
            product: "oriole",
            transport: "USB",
            state: .ready,
            adbSocket: "tcp:127.0.0.1:5038"
        )

        XCTAssertEqual(first.id, second.id)
    }
}
