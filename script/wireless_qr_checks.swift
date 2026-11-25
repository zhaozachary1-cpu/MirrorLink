// Deterministic QR protocol/lifecycle checks. No network or real pairing keys.
import CoreImage
import Foundation

private final class QRFakeADB: @unchecked Sendable {
    enum Scenario { case ready, waiting, ambiguous, pairFailure, noConnection, wrongIdentity, delayedConnection, slowPair,
        denied, deniedOnce, refused, authFailure, daemonFailure, ambiguousConnection,
        hiddenGUID, hiddenGUIDWrongHardware, hiddenGUIDFailedRead, hiddenGUIDAmbiguous, hiddenGUIDWrongEndpoint,
        connectDeniedOnce, connectDenied }
    struct Call { let args: [String]; let input: String?; let timeout: TimeInterval }
    private let lock = NSLock()
    private var name = "not-scanned"
    private var calls: [Call] = []
    private var scenario: Scenario = .ready
    private var attempts = 0
    private var pairAttempts = 0

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
        if args.first == "pair" { pairAttempts += 1 }
        let attempt = attempts
        let pairAttempt = pairAttempts
        lock.unlock()
        func result(_ text: String, status: Int32 = 0) -> ProcessResult {
            ProcessResult(status: status, stdout: text, stderr: "", timedOut: false)
        }
        let hiddenGUID = [Scenario.hiddenGUID, .hiddenGUIDWrongHardware, .hiddenGUIDFailedRead,
                          .hiddenGUIDAmbiguous, .hiddenGUIDWrongEndpoint].contains(scenario)
        let guid = hiddenGUID ? "adb-HARDWARE-SCANNED-Ab12xY" : "adb-SCANNED-abc"
        if args == ["mdns", "services"] {
            if scenario == .waiting { return result("") }
            let pairing = "\(name) _adb-tls-pairing._tcp 192.168.1.8:37123\n"
            let collision = scenario == .ambiguous ? "\(name) _adb-tls-pairing._tcp 192.168.1.9:37123\n" : ""
            let address = scenario == .hiddenGUIDWrongEndpoint ? "192.168.1.10:39847" : "192.168.1.8:39847"
            let connection = scenario == .noConnection ? "" : "\(guid) _adb-tls-connect._tcp \(address)\n"
            let duplicate = scenario == .ambiguousConnection || scenario == .hiddenGUIDAmbiguous ? "\(guid) _adb-tls-connect._tcp 192.168.1.10:39847\n" : ""
            return result("unrelated _adb-tls-pairing._tcp 192.168.1.8:37123\n" + pairing + collision + connection
                          + duplicate + "adb-OTHER-abc _adb-tls-connect._tcp 192.168.1.9:39847")
        }
        if args.first == "pair" {
            let failure: String?
            switch scenario {
            case .denied: failure = "No route to host"
            case .deniedOnce: failure = pairAttempt == 1 ? "Operation not permitted" : nil
            case .refused: failure = "Connection refused"
            case .authFailure: failure = "Failed to authenticate"
            case .daemonFailure: failure = "cannot connect to daemon"
            default: failure = nil
            }
            if let failure { return result(failure + "; echoed " + (input ?? ""), status: 1) }
            if scenario == .slowPair { Thread.sleep(forTimeInterval: 0.2) }
            return result(scenario == .pairFailure ? "Failed; echoed \(input ?? "")"
                          : "Enter pairing code: Successfully paired to 192.168.1.8:37123 [guid=\(guid)]\n")
        }
        if args.first == "connect" {
            if scenario == .connectDenied || (scenario == .connectDeniedOnce && attempt == 1) {
                return result("No route to host", status: 1)
            }
            if scenario == .delayedConnection && attempt == 1 { return result("not ready") }
            return result("connected to 192.168.1.8:39847")
        }
        if args == ["devices", "-l"] {
            return result("List of devices attached\n192.168.1.9:39847 device model:Other\n192.168.1.8:39847 device model:Scanned_Phone\n\(guid)._adb-tls-connect._tcp device model:Scanned_Phone")
        }
        if args.last == "get-state" { return result("device\n") }
        if args.last == "persist.adb.wifi.guid" {
            if hiddenGUID { return result("\n", status: scenario == .hiddenGUIDFailedRead ? 1 : 0) }
            return result(scenario == .wrongIdentity ? "adb-OTHER-abc" : "adb-SCANNED-abc\n")
        }
        if args.last == "ro.serialno" { return result(scenario == .hiddenGUIDWrongHardware ? "OTHER\n" : "HARDWARE-SCANNED\n") }
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
        let hardwareGUID = WirelessPairingIdentity(output: "Successfully paired to 192.168.1.8:37123 [guid=adb-HARDWARE-SCANNED-Ab12xY]", endpoint: endpoint)!
        try check(hardwareGUID.containsHardwareSerial("HARDWARE-SCANNED"), "AOSP six-character GUID suffix binds an exact hardware serial")
        for serial in [String?(nil), "", "HARDWARE", "SCANNED", "HARDWARE-SCANNED-Ab12xY", "OTHER"] {
            try check(!hardwareGUID.containsHardwareSerial(serial), "hardware GUID rejects missing, prefix and unrelated serial identities")
        }
        try check(!parsed.containsHardwareSerial("SCANNED"), "nonstandard GUID suffix cannot use hardware fallback")
        for scenario in [QRFakeADB.Scenario.hiddenGUID, .hiddenGUIDWrongHardware, .hiddenGUIDFailedRead, .hiddenGUIDAmbiguous, .hiddenGUIDWrongEndpoint] {
            let oem = QRFakeADB()
            oem.configure(name: "oem", scenario: scenario)
            let oemService = WirelessADBService(paths: paths, execute: { oem.run($0, $1, $2) })
            let result = try? oemService.connect(endpoint: WirelessEndpoint("192.168.1.8:39847"), expectedIdentity: hardwareGUID).get()
            try check((result != nil) == (scenario == .hiddenGUID),
                      "hidden OEM GUID requires exact hardware identity, successful property read and one matching current endpoint")
        }
        let routeFake = QRFakeADB()
        for scenario in [QRFakeADB.Scenario.connectDeniedOnce, .connectDenied] {
            let connection = QRFakeADB()
            connection.configure(name: "permission-race", scenario: scenario)
            let connectionService = WirelessADBService(paths: paths, execute: { connection.run($0, $1, $2) })
            let result = try? connectionService.connect(endpoint: WirelessEndpoint("192.168.1.8:39847")).get()
            try check((result != nil) == (scenario == .connectDeniedOnce), "one bounded permission retry recovers only a transient denial")
            let calls = connection.recorded().filter { $0.args.first == "connect" }
            try check(calls.count == 2 && calls.allSatisfy { $0.args == ["connect", "192.168.1.8:39847"] },
                      "connect retry never changes phone or restarts a daemon")
        }
        let routed = WirelessADBService(paths: paths, execute: { routeFake.run($0, $1, $2) }, adbSocket: "localfilesystem:/tmp/fixture-only/s")
        let routedDevice = try routed.connect(endpoint: WirelessEndpoint("192.168.1.8:39847"), expectedIdentity: parsed).get()
        try check(routedDevice.adbSocket == "localfilesystem:/tmp/fixture-only/s", "verified wireless device retains its owned backend route for video and tools")
        for scenario in [QRFakeADB.Scenario.denied, .refused, .authFailure, .daemonFailure] {
            let errors = QRFakeADB()
            errors.configure(name: "errors", scenario: scenario)
            let errorsService = WirelessADBService(paths: paths, execute: { errors.run($0, $1, $2) })
            guard case let .failure(error) = errorsService.pairQR(endpoint: endpoint, session: session) else {
                throw NSError(domain: "QR checks", code: 1)
            }
            try check(!error.localizedDescription.contains(session.password), "categorized QR failure never exposes echoed credential")
            let expected: String
            switch scenario {
            case .denied: expected = "本地网络"
            case .refused: expected = "关闭扫码端口"
            case .authFailure: expected = "授权已失效"
            default: expected = "调试服务不可用"
            }
            try check(error.localizedDescription.contains(expected), "QR failure gives cause-specific recovery")
            try check(errors.recorded().count == (scenario == .denied ? 2 : 1), "only transient network denial retries pairing, at most once")
        }
        let once = QRFakeADB()
        once.configure(name: "network-race", scenario: .deniedOnce)
        let raceService = WirelessADBService(paths: paths, execute: { once.run($0, $1, $2) })
        try check((try? raceService.pairQR(endpoint: endpoint, session: session).get()) == identity,
                  "privacy race can recover without a second scan")
        try check(once.recorded().count == 2 && once.recorded().allSatisfy { $0.args == ["pair", endpoint.address] },
                  "network retry is bounded to the exact scanned endpoint")
        let blocked = QRFakeADB()
        let blockedService = WirelessADBService(paths: paths, execute: { blocked.run($0, $1, $2) }, networkReadiness: { _, _, _ in false })
        try check((try? blockedService.pairQR(endpoint: endpoint, session: session).get()) == nil && blocked.recorded().isEmpty,
                  "denied native network gate cannot launch credential-bearing pairing")
        try check((try? blockedService.connect(endpoint: endpoint).get()) == nil && blocked.recorded().isEmpty,
                  "denied native network gate cannot launch connect")
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

        for scenario in [QRFakeADB.Scenario.ready, .delayedConnection, .hiddenGUID] {
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
            try check(fake.recorded().contains { $0.args == ["-s", "192.168.1.8:39847", "shell", "getprop", "persist.adb.wifi.guid"] },
                      "verify connected device GUID before mirroring")
            try check(fake.recorded().allSatisfy { !$0.args.joined().contains(secret) }, "no command arguments leak QR secret")
            if scenario == .delayedConnection {
                try check(fake.recorded().filter { $0.args.first == "connect" }.count == 2, "transient post-pair connection is retried without pairing twice")
            }
            store.stop()
        }

        for scenario in [QRFakeADB.Scenario.ambiguous, .pairFailure, .noConnection, .wrongIdentity, .waiting, .ambiguousConnection] {
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
                try check(store.canRetryConnection, "connection timeout keeps authenticated identity for a scan-free retry")
                fake.configure(name: "retry")
                store.retryConnection()
                store.retryConnection()
                try await WirelessChecks.wait { store.phase == .completed }
                try check(received == 1 && fake.recorded().filter { $0.args.first == "pair" }.count == 1,
                          "connection retry reuses only authenticated identity and ignores duplicate clicks")
            }
            if scenario == .ambiguousConnection {
                try check(!fake.recorded().contains { $0.args.first == "connect" }, "ambiguous GUID services never select the first phone")
            }
            store.stop()
            try check(!store.canRetryConnection, "close invalidates retained QR connection identity")
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
        try check(rootStore.mode == .nearby && rootStore.qr.session == nil && rootStore.isOpen, "main page discovers nearby phones without creating an unnecessary QR")
        rootStore.selectMode(.qr)
        try check(rootStore.qr.session != nil, "new-phone action explicitly starts QR pairing")
        let liveQRName = rootStore.qr.session?.serviceName
        rootStore.open()
        try check(rootStore.mode == .qr && rootStore.qr.session?.serviceName == liveQRName,
                  "refocusing the main page preserves the active QR and connection mode")
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
        try check(rootStore.connectedDeviceID == "HARDWARE-SCANNED", "successful nearby connection exposes only its target for window handoff")
        rootStore.selectMode(.manual)
        rootStore.pairingAddress = endpoint.address
        rootStore.pairingCode = "123456"
        slow.configure(name: "manual", scenario: .slowPair)
        rootStore.pair()
        rootStore.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        try check(rootStore.pairingCode.isEmpty && !rootStore.isBusy && rootStore.services.isEmpty && lateCallbacks == 2,
                  "close cancels manual callbacks and clears discovery and secret")
        try check(rootStore.connectedDeviceID == nil, "closing wireless window clears its completed handoff target")
        rootStore.selectMode(.qr)
        slow.configure(name: rootStore.qr.session!.serviceName, scenario: .hiddenGUID)
        try await WirelessChecks.wait { rootStore.qr.phase == .completed }
        try check(lateCallbacks == 3 && rootStore.connectedDeviceID == "HARDWARE-SCANNED",
                  "QR completion also targets the exact phone for window handoff")
        rootStore.close()
        try check(!rootStore.isOpen && rootStore.qr.session == nil, "closing main page stops pairing and clears QR secrets")
        rootStore.open()
        try check(rootStore.mode == .nearby && rootStore.qr.session == nil && rootStore.isOpen,
                  "reopening main page resumes nearby discovery without regenerating QR")
        rootStore.close()
    }
}
