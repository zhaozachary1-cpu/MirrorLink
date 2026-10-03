// Standalone deterministic checks. No real phone, network or pairing credentials.
import Foundation
import Darwin

private struct Failure: Error, CustomStringConvertible { let description: String }

private final class FakeADB: @unchecked Sendable {
    enum Scenario { case ready, pairFailure, connectFailure, otherPhone, alias, offline, discoveryFailure, timeout }
    struct Call { let arguments: [String]; let input: String?; let timeout: TimeInterval }
    private let lock = NSLock()
    private var scenario: Scenario = .ready
    private var calls: [Call] = []

    func set(_ scenario: Scenario) {
        lock.lock(); defer { lock.unlock() }
        self.scenario = scenario
        calls = []
    }

    func recordedCalls() -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    func run(_ arguments: [String], _ input: String?, _ timeout: TimeInterval) -> ProcessResult {
        lock.lock()
        calls.append(Call(arguments: arguments, input: input, timeout: timeout))
        let scenario = self.scenario
        lock.unlock()
        func result(_ output: String, status: Int32 = 0, timedOut: Bool = false) -> ProcessResult {
            ProcessResult(status: status, stdout: output, stderr: "", timedOut: timedOut)
        }
        if scenario == .timeout { return result("", timedOut: true) }
        if arguments.first == "pair" {
            // A tiny delay makes repeat-click checks deterministic.
            Thread.sleep(forTimeInterval: 0.04)
            return scenario == .pairFailure ? result("Failed; echoed test secret \(input ?? "")")
                : result("Enter pairing code: Successfully paired to 192.168.1.8:37123 [guid=fixture]")
        }
        if arguments.first == "connect" {
            return result(scenario == .connectFailure ? "failed to connect to 192.168.1.8:39847" : "already connected to 192.168.1.8:39847")
        }
        if arguments == ["mdns", "services"] {
            if scenario == .discoveryFailure { return result("", status: 1) }
            return result("""
            List of discovered mdns services
            adb-PHONE-one _adb-tls-pairing._tcp 192.168.1.8:37123
            adb-PHONE-one _adb-tls-connect._tcp 192.168.1.8:39847
            adb-OTHER-two _adb-tls-connect._tcp 192.168.1.9:39847
            """)
        }
        if arguments == ["devices", "-l"] {
            let serial = scenario == .alias ? "adb-PHONE-one._adb-tls-connect._tcp" : "192.168.1.8:39847"
            let line = "\(serial)\t\(scenario == .offline ? "offline" : "device") product:p model:Test_Phone"
            return result("List of devices attached\nOTHER\tdevice usb:1-1 model:Other_Phone\n" + (scenario == .otherPhone ? "" : line))
        }
        if arguments.last == "get-state" { return result(scenario == .offline ? "offline" : "device\n") }
        if arguments.suffix(3) == ["shell", "getprop", "ro.serialno"] { return result("HARDWARE123\n") }
        return result("unexpected command", status: 99)
    }
}

@main
@MainActor
struct WirelessChecks {
    static var passed = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw Failure(description: name) }
        passed += 1
        print("PASS \(passed): \(name)")
    }

    static func wait(until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() {
            guard Date() < deadline else { throw Failure(description: "async operation timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func main() async {
        do {
            try await run()
            try await WirelessQRChecks.run()
            print("PASS: \(passed) simulated wireless checks (not real Wi-Fi/video acceptance)")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func run() async throws {
        let endpoint = try WirelessEndpoint(" 192.168.1.8:39847\n")
        try check(endpoint.address == "192.168.1.8:39847", "trim and normalize IPv4 endpoint")
        try check(try WirelessEndpoint("[fd00:0:0:0::8]:65535").address == "[fd00::8]:65535", "normalize IPv6")
        try check(try WirelessEndpoint("[fe80::8%en0]:1").address == "[fe80::8%en0]:1", "IPv6 scope and minimum port")
        let invalid = ["", "192.168.1.8", "192.168.1.8:0", "192.168.1.8:65536", "256.0.1.8:30", "192.168.01.8:30", "host.local:30", "--help:30", "192.168.1.8:30;touch /tmp/bad", "192.168.1.8:+30", "192.168.1.8:３0", "http://192.168.1.8:30", "fe80::8:30", "[fe80::8%]:30", "[fe80::8%en0;bad]:30", "0.0.0.0:30", "127.0.0.1:30", "224.0.0.1:30", "255.255.255.255:30", "[::]:30", "[::1]:30", "[ff02::1]:30", "[::ffff:127.0.0.1]:30"]
        for value in invalid {
            try check((try? WirelessEndpoint(value)) == nil, "reject invalid/unsafe endpoint: \(value)")
        }

        let mdns = ADBMDNSParser.parse("""
        List of discovered mdns services
        phone-one _adb-tls-pairing._tcp 192.168.1.8:37123
        phone-one _adb-tls-connect._tcp. 192.168.1.8:39847
        phone-one _adb-tls-connect._tcp. 192.168.1.8:39847
        v6 _adb-tls-connect._tcp [fd00::8]:39847
        legacy _adb._tcp 192.168.1.8:5555
        malicious _adb-tls-connect._tcp --help:12
        corrupt row
        """)
        try check(mdns.count == 3, "mDNS parser separates pairing/connect, deduplicates, ignores legacy/malformed")
        try check(mdns.filter { $0.kind == .pairing }.count == 1, "pairing port never presented as a connection service")
        let devices = ADBDeviceParser.parse("""
        List of devices attached
        USB123 device usb:1 model:USB_Phone
        192.168.1.8:39847 device model:WiFi_Phone
        [fd00::8]:39847 offline
        adb-PHONE-one._adb-tls-connect._tcp device model:WiFi_Phone
        emulator-5554 device model:Emulator
        adb-PHONE-one._adb-tls-pairing._tcp device
        """, adbSocket: "tcp:127.0.0.1:5038")
        try check(devices.count == 4 && devices.filter(\.isWireless).count == 3, "USB, TCP, IPv6, TLS devices included; emulator and pairing excluded")
        try check(devices.allSatisfy { $0.adbSocket == "tcp:127.0.0.1:5038" }, "wireless discovery preserves alternate ADB route")
        var wireless = devices[1]
        wireless.hardwareSerial = devices[0].serial
        try check(wireless.id == devices[0].id && wireless.serial != devices[0].serial, "hardware identity is distinct from ADB transport serial")
        try check(ADBDeviceIdentity.preferred(devices[0], wireless).isWireless, "ready wireless preferred over USB for new sessions")
        try check(!ADBDeviceIdentity.preferred(devices[0], devices[2]).isWireless, "offline Wi-Fi does not hide a ready USB device")
        try check(ADBDeviceIdentity.hardwareSerial(from: ProcessResult(status: 0, stdout: "unknown\n", stderr: "", timedOut: false)) == nil, "unknown hardware serial never merges unrelated devices")

        let root = URL(fileURLWithPath: "/tmp/test-only-wireless")
        let paths = ToolPaths(root: root, adb: root, scrcpy: root, server: root)
        let fake = FakeADB()
        let service = WirelessADBService(paths: paths, execute: { fake.run($0, $1, $2) })
        let paired = try WirelessEndpoint("192.168.1.8:37123")
        _ = try service.pair(endpoint: paired, code: "123456").get()
        try check(fake.recordedCalls().first?.arguments == ["pair", paired.address], "pairing code absent from process argv")
        try check(fake.recordedCalls().first?.input == "123456\n", "pairing code only passed by stdin")
        fake.set(.ready)
        for code in ["", "12345", "1234567", "１２３４５６", "12345\n"] {
            try check((try? service.pair(endpoint: paired, code: code).get()) == nil, "invalid pairing code rejected before execution")
        }
        try check(fake.recordedCalls().isEmpty, "invalid code launches no subprocess")
        fake.set(.pairFailure)
        do {
            _ = try service.pair(endpoint: paired, code: "123456").get()
            throw Failure(description: "accepted exit-0 pair failure")
        } catch let error as WirelessConnectionError {
            try check(!error.localizedDescription.contains("123456"), "pair failure cannot echo secret input into UI or logs")
        }
        fake.set(.ready)
        let phone = try service.connect(endpoint: endpoint).get()
        try check(phone.serial == endpoint.address && phone.id == "HARDWARE123" && phone.isWireless, "connect verifies target and resolves hardware identity")
        try check(fake.recordedCalls().contains { $0.arguments == ["-s", endpoint.address, "get-state"] }, "readiness check is serial-pinned")
        try check(fake.recordedCalls().allSatisfy { $0.input == nil && $0.timeout <= 25 }, "connection operations bounded, no pairing secret reused")
        fake.set(.alias)
        let aliased = try service.connect(endpoint: endpoint).get()
        try check(aliased.serial == "adb-PHONE-one._adb-tls-connect._tcp", "already auto-connected mDNS alias resolved by exact endpoint")
        for scenario in [FakeADB.Scenario.connectFailure, .otherPhone, .offline, .timeout] {
            fake.set(scenario)
            try check((try? service.connect(endpoint: endpoint).get()) == nil, "reject failed/other-target/offline/timed-out connection")
        }
        fake.set(.discoveryFailure)
        try check(service.discover().services.isEmpty && service.discover().warning != nil, "failed discovery offers manual fallback")

        fake.set(.ready)
        var connected: [AndroidDevice] = []
        let store = WirelessConnectionStore(paths: nil, service: service) { connected.append($0) }
        store.pairingAddress = paired.address
        store.pairingCode = "123456"
        store.pair()
        store.pair()
        try check(store.isBusy && store.pairingCode.isEmpty, "pairing clears the UI secret immediately and rejects duplicate click")
        try await wait { !store.isBusy && !store.isDiscovering }
        try check(store.step == .connection && connected.isEmpty, "successful pairing advances to connect but does not claim video or start a phone")
        try check(fake.recordedCalls().filter { $0.arguments.first == "pair" }.count == 1, "only one pairing command launched")
        store.connectionAddress = paired.address
        store.connect()
        try check(store.isError && !store.isBusy && connected.isEmpty, "reusing the just-used pairing port blocked with guidance")
        store.connectionAddress = endpoint.address
        store.connect()
        try await wait { !store.isBusy }
        try check(connected.count == 1 && connected[0].serial == endpoint.address, "only verified target handed to session store")
        fake.set(.discoveryFailure)
        store.discover()
        try check(store.services.isEmpty, "discovery refresh immediately invalidates stale ports")
        try await wait { !store.isDiscovering }
        try check(store.services.isEmpty && store.discoveryMessage != nil, "failed discovery does not retain old candidates")
        store.pairingCode = "123456"
        store.clearSecret()
        try check(store.pairingCode.isEmpty, "window dismissal clears pairing secret")
        let missing = WirelessConnectionStore(paths: nil) { _ in }
        missing.discover()
        try check(missing.isError && !missing.isDiscovering, "missing bundled tool fails closed")

        let stdin = ProcessRunner.run(executablePath: "/bin/cat", arguments: [], standardInput: "fixture\n", timeout: 2)
        try check(stdin.succeeded && stdin.stdout == "fixture\n", "real subprocess stdin and EOF plumbing works")
        let earlyExit = ProcessRunner.run(executablePath: "/usr/bin/true", arguments: [], standardInput: "fixture\n", timeout: 2)
        try check(earlyExit.succeeded, "child rejecting stdin cannot terminate the host")
        let timeout = ProcessRunner.run(executablePath: "/bin/sleep", arguments: ["2"], timeout: 0.05)
        try check(timeout.timedOut && !timeout.succeeded, "hung process deadline enforced")
    }
}
