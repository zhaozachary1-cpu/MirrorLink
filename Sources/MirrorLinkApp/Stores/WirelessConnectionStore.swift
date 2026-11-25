import Combine
import Foundation

enum WirelessConnectionStep: String, CaseIterable {
    case pairing = "首次配对"
    case connection = "连接手机"

    var title: String { L10n.tr(rawValue) }
}

enum WirelessConnectionMode: String, CaseIterable {
    case qr = "扫码配对"
    case nearby = "发现手机"
    case manual = "手动连接"

    var title: String { L10n.tr(rawValue) }
}

@MainActor
final class WirelessConnectionStore: ObservableObject {
    @Published private(set) var mode: WirelessConnectionMode = .nearby
    @Published var step: WirelessConnectionStep = .pairing
    @Published var pairingAddress = ""
    @Published var connectionAddress = ""
    @Published var pairingCode = ""
    @Published private(set) var services: [WirelessService] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var connectedDeviceID: AndroidDevice.ID?
    @Published private var messageValue: LocalizedMessage?
    var message: String? { messageValue?.resolved }
    @Published private(set) var isError = false
    @Published private var discoveryMessageValue: LocalizedMessage?
    var discoveryMessage: String? { discoveryMessageValue?.resolved }

    private let service: WirelessADBService?
    private let onConnected: (AndroidDevice) -> Void
    private var discoveryGeneration = 0
    private var lastPairedEndpoint: WirelessEndpoint?
    private var operationGeneration = 0
    private var cancellation = ProcessCancellation()
    private var nearbyTask: Task<Void, Never>?
    private(set) var isOpen = false
    lazy var qr = WirelessQRPairingStore(service: service) { [weak self] device in
        self?.didConnect(device)
    }

    init(paths: ToolPaths?, service: WirelessADBService? = nil, onConnected: @escaping (AndroidDevice) -> Void) {
        let resolvedService = service ?? paths.map { WirelessADBService(paths: $0) }
        self.service = resolvedService
        self.onConnected = onConnected
    }

    // Repeated key-window notifications and language refreshes must not restart
    // discovery, discard form values or replace a live pairing QR.
    func open() {
        guard !isOpen else { return }
        selectMode(.nearby)
    }

    func selectMode(_ mode: WirelessConnectionMode) {
        close()
        self.mode = mode
        isOpen = true
        messageValue = nil
        isError = false
        if mode == .qr { qr.start() }
        else if mode == .nearby {
            step = .connection
            nearbyTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.discover(preservingServices: true)
                    do { try await Task.sleep(nanoseconds: 4_000_000_000) }
                    catch { return }
                }
            }
        } else { discover() }
    }

    func close() {
        isOpen = false
        qr.stop()
        nearbyTask?.cancel()
        nearbyTask = nil
        cancellation.cancel()
        cancellation = ProcessCancellation()
        operationGeneration += 1
        discoveryGeneration += 1
        pairingCode = ""
        connectedDeviceID = nil
        services = []
        discoveryMessageValue = nil
        isBusy = false
        isDiscovering = false
    }

    func connectDiscovered(_ candidate: WirelessService) {
        guard candidate.kind == .connection, services.contains(candidate), !isBusy else { return }
        connectionAddress = candidate.endpoint.address
        connect()
    }

    var visibleServices: [WirelessService] {
        services.filter { $0.kind == (step == .pairing ? .pairing : .connection) }
    }

    func choose(_ service: WirelessService) {
        guard !isBusy else { return }
        if service.kind == .pairing { pairingAddress = service.endpoint.address }
        else { connectionAddress = service.endpoint.address }
    }

    func discover(preservingServices: Bool = false) {
        guard !isBusy, !isDiscovering else { return }
        guard let service else { show(WirelessConnectionError.toolsMissing); return }
        isDiscovering = true
        discoveryGeneration += 1
        let generation = discoveryGeneration
        let token = cancellation
        // Keep rows stable during passive refresh. The result always replaces
        // them (including on failure); explicit refresh still clears immediately.
        if !preservingServices { services = [] }
        discoveryMessageValue = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = service.discover(cancellation: token)
            DispatchQueue.main.async {
                guard let self, generation == self.discoveryGeneration else { return }
                self.isDiscovering = false
                self.services = result.services
                self.discoveryMessageValue = result.warningMessage
            }
        }
    }

    func pair() {
        guard !isBusy else { return }
        let code = pairingCode
        pairingCode = ""
        do {
            let endpoint = try WirelessEndpoint(pairingAddress)
            guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw WirelessConnectionError.invalidPairingCode
            }
            guard let service else { throw WirelessConnectionError.toolsMissing }
            beginOperation(L10n.message("正在与手机配对…"))
            let generation = operationGeneration
            let token = cancellation
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = service.pair(endpoint: endpoint, code: code, cancellation: token)
                DispatchQueue.main.async {
                    guard let self, generation == self.operationGeneration else { return }
                    self.isBusy = false
                    switch result {
                    case .success:
                        self.lastPairedEndpoint = endpoint
                        self.connectionAddress = ""
                        self.step = .connection
                        self.messageValue = L10n.message("配对成功，请选择下方手机连接，或填写手机的连接地址。")
                        self.discover()
                    case let .failure(error): self.show(error)
                    }
                }
            }
        } catch { show(error) }
    }

    func connect() {
        guard !isBusy else { return }
        do {
            let endpoint = try WirelessEndpoint(connectionAddress)
            guard endpoint != lastPairedEndpoint else {
                show(L10n.message("这是配对端口，请填写手机的连接端口。"))
                return
            }
            guard let service else { throw WirelessConnectionError.toolsMissing }
            beginOperation(L10n.message("正在连接并确认手机状态…"))
            let generation = operationGeneration
            let token = cancellation
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = service.connect(endpoint: endpoint, cancellation: token)
                DispatchQueue.main.async {
                    guard let self, generation == self.operationGeneration else { return }
                    self.isBusy = false
                    switch result {
                    case let .success(device):
                        self.messageValue = L10n.message("已连接，正在打开投屏窗口…")
                        self.didConnect(device)
                    case let .failure(error): self.show(error)
                    }
                }
            }
        } catch { show(error) }
    }

    func clearSecret() { pairingCode = "" }

    private func didConnect(_ device: AndroidDevice) {
        connectedDeviceID = device.id
        onConnected(device)
    }

    private func beginOperation(_ text: LocalizedMessage) {
        connectedDeviceID = nil
        discoveryGeneration += 1
        isDiscovering = false
        discoveryMessageValue = nil
        isBusy = true
        isError = false
        messageValue = text
    }

    private func show(_ error: Error) {
        show((error as? WirelessConnectionError)?.localizedMessage ?? .verbatim(error.localizedDescription))
    }

    private func show(_ text: LocalizedMessage) {
        isError = true
        messageValue = text
    }
}
