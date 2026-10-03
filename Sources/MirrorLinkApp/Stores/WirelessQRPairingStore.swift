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
    @Published private(set) var message = ""
    @Published private(set) var discoveryWarning: String?

    private let service: WirelessADBService?
    private let onConnected: (AndroidDevice) -> Void
    private let lifetime: TimeInterval
    private let connectionWait: TimeInterval
    private let pollInterval: TimeInterval
    private var cancellation: ProcessCancellation?
    private var task: Task<Void, Never>?
    private var generation = UUID()

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
        guard let service else { fail(WirelessConnectionError.toolsMissing.localizedDescription); return }
        do {
            session = try WirelessQRSession(lifetime: lifetime)
        } catch { fail(error.localizedDescription); return }
        let token = ProcessCancellation()
        cancellation = token
        let id = generation
        phase = .waitingForScan
        message = "等待手机扫码，正在自动发现…"
        task = Task { [weak self] in
            guard let self else { return }
            // The helper releases its QR credential before the connection stage.
            guard let identity = await self.waitForPairing(service: service, token: token, id: id),
                  self.isCurrent(id) else { return }
            self.session = nil
            self.phase = .connecting
            self.message = "配对成功，正在自动连接这台手机…"
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
        discoveryWarning = nil
        phase = .idle
        message = "已停止扫码发现。已完成的手机授权不会自动撤销，可在手机中手动忘记此电脑。"
    }

    private func isCurrent(_ id: UUID) -> Bool { generation == id && !Task.isCancelled }

    private func waitForPairing(service: WirelessADBService, token: ProcessCancellation,
                                id: UUID) async -> WirelessPairingIdentity? {
        guard let session else { return nil }
        while isCurrent(id), Date() < session.expiresAt {
            let discovery = await Task.detached { service.discover(cancellation: token) }.value
            guard isCurrent(id) else { return nil }
            guard Date() < session.expiresAt else { break }
            discoveryWarning = discovery.warning
            let matches = discovery.services.filter(session.matches)
            if matches.count > 1 {
                fail("多处服务响应了同一个二维码。请一次只用一台手机扫码，然后生成新二维码重试。")
                return nil
            }
            if let match = matches.first {
                phase = .pairing
                message = "已发现扫码的手机，正在安全配对…"
                // Hide the single-use QR immediately so another phone cannot scan it.
                self.session = nil
                let result = await Task.detached {
                    service.pairQR(endpoint: match.endpoint, session: session, cancellation: token)
                }.value
                guard isCurrent(id) else { return nil }
                switch result {
                case let .success(identity): return identity
                case let .failure(error): fail(error.localizedDescription); return nil
                }
            }
            do { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
            catch { return nil }
        }
        if isCurrent(id) { fail("二维码已过期。点击“生成新二维码”后重新扫描。") }
        return nil
    }

    private func waitForConnection(_ identity: WirelessPairingIdentity, service: WirelessADBService,
                                   token: ProcessCancellation, id: UUID) async {
        let deadline = Date().addingTimeInterval(connectionWait)
        var lastError: String?
        while isCurrent(id), Date() < deadline {
            let discovery = await Task.detached { service.discover(cancellation: token) }.value
            guard isCurrent(id) else { return }
            if let target = discovery.services.first(where: identity.matches), Date() < deadline {
                let result = await Task.detached {
                    service.connect(endpoint: target.endpoint, expectedIdentity: identity, cancellation: token)
                }.value
                guard isCurrent(id) else { return }
                switch result {
                case let .success(device):
                    phase = .completed
                    discoveryWarning = nil
                    message = "已连接扫码的手机，已请求开始投屏。画面与启动结果请查看主窗口。"
                    onConnected(device)
                    return
                case let .failure(error): lastError = error.localizedDescription
                }
            }
            do { try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000)) }
            catch { return }
        }
        if isCurrent(id) {
            fail(lastError ?? "已配对，但暂未发现这台手机的连接服务。请返回手机无线调试主页面，使用“发现手机”重试；网络不支持发现时可用“手动连接”。无需重复配对。")
        }
    }

    private func fail(_ text: String) {
        session = nil
        discoveryWarning = nil
        phase = .failed
        message = text
    }
}
