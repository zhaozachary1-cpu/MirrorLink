// Deterministic QR protocol/lifecycle checks. No network or real pairing keys.
import CoreImage
import Foundation

private final class QRFakeADB: @unchecked Sendable {
    enum Scenario { case ready, waiting, ambiguous, pairFailure, noConnection, wrongIdentity, delayedConnection, slowPair }
    struct Call { let args: [String]; let input: String?; let timeout: TimeInterval }
    private let lock = NSLock()
    private var name = "not-scanned"
    private var calls: [Call] = []
    private var scenario: Scenario = .ready
    private var attempts = 0

    func configure(name: String, scenario: Scenario = .ready) {
        lock.lock(); defer { lock.unlock() }
        self.name = name
        self.scenario = scenario
    }

    func recorded() -> [Call] { lock.lock(); defer { lock.unlock() }; return calls }

    func run(_ args: [String], _ input: String?, _ timeout: TimeInterval) -> ProcessResult {
        lock.lock()
        calls.append(Call(args: args, input: input, timeout: timeout))
        let name = self.name
        let scenario = self.scenario
        if args.first == "connect" { attempts += 1 }
        let attempt = attempts
        lock.unlock()
        func result(_ text: String, status: Int32 = 0) -> ProcessResult {
            ProcessResult(status: status, stdout: text, stderr: "", timedOut: false)
        }
        if args == ["mdns", "services"] {
            if scenario == .waiting { return result("") }
            let pairing = "\(name) _adb-tls-pairing._tcp 192.168.1.8:37123\n"
            let collision = scenario == .ambiguous ? "\(name) _adb-tls-pairing._tcp 192.168.1.9:37123\n" : ""
            let connection = scenario == .noConnection ? "" : "adb-SCANNED-abc _adb-tls-connect._tcp 192.168.1.8:39847\n"
            return result("unrelated _adb-tls-pairing._tcp 192.168.1.8:37123\n" + pairing + collision + connection
                          + "adb-OTHER-abc _adb-tls-connect._tcp 192.168.1.9:39847")
        }
        if args.first == "pair" {
            if scenario == .slowPair { Thread.sleep(forTimeInterval: 0.2) }
            return result(scenario == .pairFailure ? "Failed; echoed \(input ?? "")"
                          : "Enter pairing code: Successfully paired to 192.168.1.8:37123 [guid=adb-SCANNED-abc]\n")
        }
        if args.first == "connect" {
            if scenario == .delayedConnection && attempt == 1 { return result("not ready") }
            return result("connected to 192.168.1.8:39847")
        }
        if args == ["devices", "-l"] {
            return result("List of devices attached\n192.168.1.9:39847 device model:Other\nadb-SCANNED-abc._adb-tls-connect._tcp device model:Scanned_Phone")
        }
        if args.last == "get-state" { return result("device\n") }
        if args.last == "persist.adb.wifi.guid" { return result(scenario == .wrongIdentity ? "adb-OTHER-abc" : "adb-SCANNED-abc\n") }
        if args.last == "ro.serialno" { return result("HARDWARE-SCANNED\n") }
        return result("unexpected", status: 99)
    }
}

@MainActor
enum WirelessQRChecks {
    static func run() async throws {
        func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            try WirelessChecks.check(value(), name)
        }
        let session = try WirelessQRSession()
        let other = try WirelessQRSession()
        try check(session.password.count == 32 && session.serviceName.count <= 63, "QR uses 128-bit random password and bounded mDNS label")
        try check(session.password != other.password && session.serviceName != other.serviceName, "QR credentials and names rotate per session")
        try check(session.payload == "WIFI:T:ADB;S:\(session.serviceName);P:\(session.password);;", "native Android QR payload")
        try check(!String(describing: session).contains(session.password) && !String(reflecting: session).contains(session.password), "debug descriptions redact QR credential")
        try check(session.expiresAt.timeIntervalSinceNow > 118 && session.expiresAt.timeIntervalSinceNow <= 120, "default QR validity is two minutes")
        let image = WirelessQRCode.image(for: session)
        try check(image != nil, "native CoreImage QR renders")
        if let image {
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
            let features = detector?.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature]
            try check(features?.first?.messageString == session.payload, "rendered QR decodes to exact Android pairing payload")
        }
        let endpoint = try WirelessEndpoint("192.168.1.8:37123")
        let acknowledged = "Enter pairing code: Successfully paired to 192.168.1.8:37123 [guid=adb-SCANNED-abc]"
        let identity = WirelessPairingIdentity(output: acknowledged, endpoint: endpoint)
        try check(identity?.guid == "adb-SCANNED-abc", "parse authenticated GUID even with stdin prompt prefix")
        for text in ["Successfully paired to 192.168.1.9:37123 [guid=wrong]", "Successfully paired to 192.168.1.8:37123",
                     "Successfully paired to 192.168.1.8:37123 [guid=]", "Successfully paired to 192.168.1.8:37123 [guid=x;bad]",
                     "failed [guid=adb-SCANNED-abc]"] {
            try check(WirelessPairingIdentity(output: text, endpoint: endpoint) == nil, "reject wrong endpoint, missing or unsafe pairing identity")
        }
        let root = URL(fileURLWithPath: "/tmp/test-only-qr")
        let paths = ToolPaths(root: root, adb: root, scrcpy: root, server: root)
        let fake = QRFakeADB()
        let service = WirelessADBService(paths: paths, execute: { fake.run($0, $1, $2) })
        let parsed = try service.pairQR(endpoint: endpoint, session: session).get()
        try check(parsed == identity, "QR pairing returns authenticated identity")
        try check(fake.recorded().last?.args == ["pair", endpoint.address], "QR secret never placed in argv")
        try check(fake.recorded().last?.input == session.password + "\n", "QR password passed only to stdin")
        let expired = try WirelessQRSession(lifetime: -1)
        let count = fake.recorded().count
        try check((try? service.pairQR(endpoint: endpoint, session: expired).get()) == nil && fake.recorded().count == count,
                  "expired QR cannot launch pairing command")
        let slowExpiry = QRFakeADB()
        slowExpiry.configure(name: "expires-during-pairing", scenario: .slowPair)
        let expiryService = WirelessADBService(paths: paths, execute: { slowExpiry.run($0, $1, $2) })
        let expiring = try WirelessQRSession(lifetime: 0.08)
        try check((try? expiryService.pairQR(endpoint: endpoint, session: expiring).get()) == nil,
                  "late pairing success after QR expiry cannot trigger automatic connection")
        try check((slowExpiry.recorded().last?.timeout ?? 100) <= 0.08,
                  "pairing timeout is bounded by remaining QR lifetime")
        let announcements = service.discover().services
        try check(announcements.filter { $0.endpoint == endpoint }.count == 2, "same endpoint with distinct service names retains QR match")
        try check(!session.matches(announcements[0]), "unrelated service name never treated as scanned phone")
        try check(identity?.matches(WirelessService(name: "adb-SCANNED-abc", kind: .pairing, endpoint: endpoint)) == false,
                  "pairing port never used for QR connection stage")

        for scenario in [QRFakeADB.Scenario.ready, .delayedConnection] {
            let fake = QRFakeADB()
            let service = WirelessADBService(paths: paths, execute: { fake.run($0, $1, $2) })
            var received: [AndroidDevice] = []
            let store = WirelessQRPairingStore(service: service, pollInterval: 0.02) { received.append($0) }
            store.start()
            try check(store.phase == .waitingForScan && store.session != nil, "open QR starts active discovery")
            let secret = store.session!.password
            fake.configure(name: store.session!.serviceName, scenario: scenario)
            try await WirelessChecks.wait { store.phase == .completed }
            try check(received.count == 1 && received[0].id == "HARDWARE-SCANNED", "QR automatically mirrors only authenticated scanned phone")
            try check(store.session == nil && !store.message.contains(secret), "QR credential cleared after pairing, UI status redacted")
            try check(fake.recorded().filter { $0.args.first == "pair" }.count == 1, "one scan sends only one pairing command")
            try check(fake.recorded().filter { $0.args.first == "connect" }.allSatisfy { $0.args == ["connect", "192.168.1.8:39847"] }, "never connects other nearby phone")
            try check(fake.recorded().contains { $0.args == ["-s", "adb-SCANNED-abc._adb-tls-connect._tcp", "shell", "getprop", "persist.adb.wifi.guid"] },
                      "verify connected device GUID before mirroring")
            try check(fake.recorded().allSatisfy { !$0.args.joined().contains(secret) }, "no command arguments leak QR secret")
            if scenario == .delayedConnection {
                try check(fake.recorded().filter { $0.args.first == "connect" }.count == 2, "transient post-pair connection is retried without pairing twice")
            }
            store.stop()
        }

        for scenario in [QRFakeADB.Scenario.ambiguous, .pairFailure, .noConnection, .wrongIdentity, .waiting] {
            let fake = QRFakeADB()
            let service = WirelessADBService(paths: paths, execute: { fake.run($0, $1, $2) })
            var received = 0
            let store = WirelessQRPairingStore(service: service, lifetime: 0.2, connectionWait: 0.15, pollInterval: 0.02) { _ in received += 1 }
            store.start()
            let secret = store.session!.password
            fake.configure(name: store.session!.serviceName, scenario: scenario)
            try await WirelessChecks.wait { store.phase == .failed }
            try check(received == 0 && store.session == nil, "ambiguous/failed/absent/mismatched/expired QR never mirrors a phone")
            try check(!store.message.contains(secret), "QR failure output cannot echo secret")
            if scenario == .ambiguous || scenario == .waiting {
                try check(!fake.recorded().contains { $0.args.first == "pair" }, "no speculative pairing of ambiguous or undiscovered phones")
            }
            if scenario == .noConnection {
                try check(!fake.recorded().contains { $0.args.first == "connect" }, "no host-IP guessing when matching connect GUID absent")
            }
            store.stop()
        }

        let slow = QRFakeADB()
        let slowService = WirelessADBService(paths: paths, execute: { slow.run($0, $1, $2) })
        var lateCallbacks = 0
        let cancelStore = WirelessQRPairingStore(service: slowService, pollInterval: 0.02) { _ in lateCallbacks += 1 }
        cancelStore.start()
        slow.configure(name: cancelStore.session!.serviceName, scenario: .slowPair)
        try await WirelessChecks.wait { slow.recorded().contains { $0.args.first == "pair" } }
        cancelStore.stop()
        try check(cancelStore.session == nil && cancelStore.phase == .idle, "close clears QR immediately during in-flight pairing")
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(lateCallbacks == 0 && !slow.recorded().contains { $0.args.first == "connect" }, "late pairing result cannot connect or mirror after cancel")
        cancelStore.start()
        let oldName = cancelStore.session!.serviceName
        cancelStore.start()
        slow.configure(name: oldName)
        try await Task.sleep(nanoseconds: 90_000_000)
        try check(cancelStore.phase == .waitingForScan && cancelStore.session?.serviceName != oldName, "regeneration ignores stale QR announcements")
        slow.configure(name: cancelStore.session!.serviceName)
        try await WirelessChecks.wait { cancelStore.phase == .completed }
        try check(lateCallbacks == 1, "new generation can connect once after cancellation")
        cancelStore.stop()
        let missing = WirelessQRPairingStore(service: nil) { _ in }
        missing.start()
        try check(missing.phase == .failed && missing.session == nil, "missing ADB fails before QR display")

        let token = ProcessCancellation()
        let running = Task.detached { ProcessRunner.run(executablePath: "/bin/sleep", arguments: ["5"], timeout: 10, cancellation: token) }
        try await Task.sleep(nanoseconds: 80_000_000)
        token.cancel()
        let cancelled = await running.value
        try check(!cancelled.succeeded && !cancelled.timedOut, "cancellation stops only owned subprocess before its timeout")
        let skipped = ProcessRunner.run(executablePath: "/does-not-exist", arguments: [], cancellation: token)
        try check(skipped.status == -999 && skipped.stderr.isEmpty, "already-cancelled operation never spawns a subprocess")

        let rootStore = WirelessConnectionStore(paths: nil, service: slowService) { _ in lateCallbacks += 1 }
        rootStore.open()
        try check(rootStore.mode == .qr && rootStore.qr.session != nil, "wireless window defaults to QR")
        rootStore.selectMode(.nearby)
        try check(rootStore.qr.session == nil && rootStore.step == .connection, "switch to nearby cancels QR and selects connection services")
        try await WirelessChecks.wait { !rootStore.services.isEmpty }
        let visibleBeforeRefresh = rootStore.services
        rootStore.discover(preservingServices: true)
        try check(rootStore.isDiscovering && rootStore.services == visibleBeforeRefresh,
                  "passive discovery keeps phone rows stable while refreshing")
        try await WirelessChecks.wait { !rootStore.isDiscovering }
        slow.configure(name: "none", scenario: .waiting)
        rootStore.discover(preservingServices: true)
        try await WirelessChecks.wait { !rootStore.isDiscovering }
        try check(rootStore.services.isEmpty, "passive discovery removes stale phone rows when no services remain")
        slow.configure(name: "manual")
        rootStore.discover()
        try await WirelessChecks.wait { !rootStore.isDiscovering }
        let candidate = rootStore.visibleServices.first { $0.name == "adb-SCANNED-abc" }!
        rootStore.connectDiscovered(candidate)
        rootStore.connectDiscovered(candidate)
        try await WirelessChecks.wait { !rootStore.isBusy }
        try check(lateCallbacks == 2, "one-click discovered phone connects without address copying and ignores duplicate clicks")
        rootStore.selectMode(.manual)
        rootStore.pairingAddress = endpoint.address
        rootStore.pairingCode = "123456"
        slow.configure(name: "manual", scenario: .slowPair)
        rootStore.pair()
        rootStore.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(rootStore.pairingCode.isEmpty && !rootStore.isBusy && rootStore.services.isEmpty && lateCallbacks == 2,
                  "close cancels manual callbacks and clears discovery and secret")
    }
}
