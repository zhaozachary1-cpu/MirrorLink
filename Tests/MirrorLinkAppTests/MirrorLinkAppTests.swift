import XCTest
@testable import MirrorLinkApp

final class MirrorLinkAppTests: XCTestCase {
    func testWirelessEndpointValidationAndNormalization() throws {
        XCTAssertEqual(try WirelessEndpoint("192.168.1.8:37123").address, "192.168.1.8:37123")
        XCTAssertEqual(try WirelessEndpoint("[fd00:0::8]:37123").address, "[fd00::8]:37123")
        for address in ["127.0.0.1:30", "192.168.01.8:30", "192.168.1.8:0", "host.local:30", "192.168.1.8:30;echo bad"] {
            XCTAssertThrowsError(try WirelessEndpoint(address))
        }
    }

    func testWirelessDiscoverySeparatesPairingAndConnectionPorts() {
        let services = ADBMDNSParser.parse("""
        List of discovered mdns services
        adb-TEST-one _adb-tls-pairing._tcp 192.168.1.8:37123
        adb-TEST-one _adb-tls-connect._tcp 192.168.1.8:39847
        """)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services.first(where: { $0.kind == .pairing })?.endpoint.port, 37123)
        XCTAssertEqual(services.first(where: { $0.kind == .connection })?.endpoint.port, 39847)
    }

    func testScrcpyTargetsWirelessTransportInsteadOfHardwareOrSessionIdentity() {
        let root = URL(fileURLWithPath: "/tmp/mirrorlink/tools")
        let paths = ToolPaths(root: root, adb: root.appendingPathComponent("adb"), scrcpy: root.appendingPathComponent("scrcpy"), server: root.appendingPathComponent("scrcpy-server"))
        var device = AndroidDevice(serial: "192.168.1.8:39847", model: "Phone", product: nil, transport: "Wi-Fi", state: .ready, adbSocket: nil)
        device.hardwareSerial = "HARDWARE"
        device.sessionIdentity = "EXISTING-SESSION"
        let command = ScrcpyCommand(paths: paths)
        XCTAssertEqual(Array(command.arguments(for: device).prefix(2)), ["-s", device.serial])
        XCTAssertEqual(command.environment(for: device)["ANDROID_SERIAL"], device.serial)
        XCTAssertEqual(device.id, "EXISTING-SESSION")
    }

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
