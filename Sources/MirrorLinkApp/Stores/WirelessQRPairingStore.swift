import Combine
import Foundation

enum WirelessQRPhase: Equatable {
    case idle, waitingForScan, pairing, connecting, completed, failed
    var isActive: Bool { self == .waitingForScan || self == .pairing || self == .connecting }
}

@MainActor
final class WirelessQRPairingStore: ObservableObject {
    @Published private(set) var session: WirelessQRSession?
    @Published private(set) var phase: WirelessQRPhase = .idle
    @Published private var messageValue = L10n.message("")
    var message: String { messageValue.resolved }
    @Published private var discoveryWarningValue: LocalizedMessage?
    var discoveryWarning: String? { discoveryWarningValue?.resolved }

    private let service: WirelessADBService?
    private let onConnected: (AndroidDevice) -> Void
    private let lifetime: TimeInterval
    private let connectionWait: TimeInterval
    private let pollInterval: TimeInterval
    private var cancellation: ProcessCancellation?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pairedIdentity: WirelessPairingIdentity?
    var canRetryConnection: Bool { pairedIdentity != nil && phase == .failed }

    init(service: WirelessADBService?, lifetime: TimeInterval = 120,
         connectionWait: TimeInterval = 35, pollInterval: TimeInterval = 1.5,
         onConnected: @escaping (AndroidDevice) -> Void) {
        self.service = service
        self.lifetime = lifetime
        self.connectionWait = connectionWait
        self.pollInterval = pollInterval
        self.onConnected = onConnected
    }

    func start() {
        stop()
        guard let service else { fail(WirelessConnectionError.toolsMissing.localizedMessage); return }
        do {
            session = try WirelessQRSession(lifetime: lifetime)
        } catch {
            fail((error as? WirelessConnectionError)?.localizedMessage ?? .verbatim(error.localizedDescription))
            return
        }
        let token = ProcessCancellation()
        cancellation = token
        let id = generation
        phase = .waitingForScan
        messageValue = L10n.message("等待手机扫码，正在自动发现…")
        task = Task { [weak self] in
            guard let self else { return }
            // The helper releases its QR credential before the connection stage.
            guard let identity = await self.waitForPairing(service: service, token: token, id: id),
                  self.isCurrent(id) else { return }
            self.pairedIdentity = identity
            self.session = nil
            self.phase = .connecting
            self.messageValue = L10n.message("配对成功，正在自动连接这台手机…")
            await self.waitForConnection(identity, service: service, token: token, id: id)
        }
    }

    func stop() {
        generation = UUID()
        cancellation?.cancel()
        cancellation = nil
        task?.cancel()
        task = nil
        session = nil
        pairedIdentity = nil
        discoveryWarningValue = nil
        phase = .idle
        messageValue = L10n.message("扫码已取消，已有手机授权保留。")
    }

    func retryConnection() {
        guard canRetryConnection, let identity = pairedIdentity, let service else { return }
        cancellation?.cancel()
        task?.cancel()
        generation = UUID()
        let id = generation
        let token = ProcessCancellation()
        cancellation = token
        phase = .connecting
        messageValue = L10n.message("配对成功，正在自动连接这台手机…")
        task = Task { [weak self] in
            await self?.waitForConnection(identity, service: service, token: token, id: id)
        }
    }

    private func isCurrent(_ id: UUID) -> Bool { generation == id && !Task.isCancelled }

    private func waitForPairing(service: WirelessADBService, token: ProcessCancellation,
                                id: UUID) async -> WirelessPairingIdentity? {
        guard let session else { return nil }
        while isCurrent(id), Date() < session.expiresAt {
            let discovery = await Task.detached { service.discover(cancellation: token) }.value
            guard isCurrent(id) else { return nil }
            guard Date() < session.expiresAt else { break }
            discoveryWarningValue = discovery.warningMessage
            let matches = discovery.services.filter(session.matches)
            if matches.count > 1 {
                fail(L10n.message("多台手机同时响应，请逐台扫码。"))
                return nil
            }
            if let match = matches.first {
                phase = .pairing
                messageValue = L10n.message("已发现扫码的手机，正在安全配对…")
                // Hide the single-use QR immediately so another phone cannot scan it.
                self.session = nil
                let result = await Task.detached {
                    service.pairQR(endpoint: match.endpoint, session: session, cancellation: token)
                }.value
                guard isCurrent(id) else { return nil }
                switch result {
                case let .success(identity): return identity
                case let .failure(error): fail(error.localizedMessage); return nil
                }
            }
            do { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
            catch { return nil }
        }
        if isCurrent(id) { fail(L10n.message("二维码已过期，请刷新后再扫。")) }
        return nil
    }

    private func waitForConnection(_ identity: WirelessPairingIdentity, service: WirelessADBService,
                                   token: ProcessCancellation, id: UUID) async {
        let deadline = Date().addingTimeInterval(connectionWait)
        var lastError: LocalizedMessage?
        while isCurrent(id), Date() < deadline {
            let discovery = await Task.detached { service.discover(cancellation: token) }.value
            guard isCurrent(id) else { return }
            let matches = discovery.services.filter(identity.matches)
            if matches.count > 1 {
                fail(L10n.message("发现重复手机，请手动核对连接地址。"))
                return
            }
            if let target = matches.first, Date() < deadline {
                let result = await Task.detached {
                    service.connect(endpoint: target.endpoint, expectedIdentity: identity, cancellation: token)
                }.value
                guard isCurrent(id) else { return }
                switch result {
                case let .success(device):
                    phase = .completed
                    discoveryWarningValue = nil
                    messageValue = L10n.message("已连接，正在打开投屏窗口…")
                    onConnected(device)
                    return
                case let .failure(error): lastError = error.localizedMessage
                }
            }
            do { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
            catch { return }
        }
        if isCurrent(id) {
            fail(lastError ?? L10n.message("已配对但未连上，请重试连接，无需重新扫码。"))
        }
    }

    private func fail(_ text: LocalizedMessage) {
        session = nil
        discoveryWarningValue = nil
        phase = .failed
        messageValue = text
    }
}
