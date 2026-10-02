import Combine
import Foundation

enum WirelessConnectionStep: String, CaseIterable {
    case pairing = "首次配对"
    case connection = "连接手机"
}

@MainActor
final class WirelessConnectionStore: ObservableObject {
    @Published var step: WirelessConnectionStep = .pairing
    @Published var pairingAddress = ""
    @Published var connectionAddress = ""
    @Published var pairingCode = ""
    @Published private(set) var services: [WirelessService] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    @Published private(set) var discoveryMessage: String?

    private let service: WirelessADBService?
    private let onConnected: (AndroidDevice) -> Void
    private var discoveryGeneration = 0
    private var lastPairedEndpoint: WirelessEndpoint?

    init(paths: ToolPaths?, service: WirelessADBService? = nil, onConnected: @escaping (AndroidDevice) -> Void) {
        self.service = service ?? paths.map { WirelessADBService(paths: $0) }
        self.onConnected = onConnected
    }

    var visibleServices: [WirelessService] {
        services.filter { $0.kind == (step == .pairing ? .pairing : .connection) }
    }

    func choose(_ service: WirelessService) {
        guard !isBusy else { return }
        if service.kind == .pairing { pairingAddress = service.endpoint.address }
        else { connectionAddress = service.endpoint.address }
    }

    func discover() {
        guard !isBusy, !isDiscovering else { return }
        guard let service else { show(WirelessConnectionError.toolsMissing); return }
        isDiscovering = true
        discoveryGeneration += 1
        let generation = discoveryGeneration
        // Clear stale ports immediately, even when this refresh fails.
        services = []
        discoveryMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = service.discover()
            DispatchQueue.main.async {
                guard let self, generation == self.discoveryGeneration else { return }
                self.isDiscovering = false
                self.services = result.services
                self.discoveryMessage = result.warning
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
            beginOperation("正在与手机配对…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = service.pair(endpoint: endpoint, code: code)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    switch result {
                    case .success:
                        self.lastPairedEndpoint = endpoint
                        self.connectionAddress = ""
                        self.step = .connection
                        self.message = "配对成功。请返回手机“无线调试”主页面，使用其中的连接地址；配对成功还不等于已连接投屏。"
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
                throw WirelessConnectionError.failed("这里仍是刚才的配对端口。请返回手机“无线调试”主页面，填写该页面的连接端口。")
            }
            guard let service else { throw WirelessConnectionError.toolsMissing }
            beginOperation("正在连接并确认手机状态…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = service.connect(endpoint: endpoint)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    switch result {
                    case let .success(device):
                        self.message = "设备已连接，已请求启动投屏。画面与启动结果请查看主窗口。"
                        self.onConnected(device)
                    case let .failure(error): self.show(error)
                    }
                }
            }
        } catch { show(error) }
    }

    func clearSecret() { pairingCode = "" }

    private func beginOperation(_ text: String) {
        discoveryGeneration += 1
        isDiscovering = false
        services = []
        discoveryMessage = nil
        isBusy = true
        isError = false
        message = text
    }

    private func show(_ error: Error) {
        isError = true
        message = error.localizedDescription
    }
}
