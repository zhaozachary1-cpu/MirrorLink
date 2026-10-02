import Foundation

enum DeviceConnectionState: String, CaseIterable, Sendable {
    case ready = "device"
    case unauthorized
    case offline
    case unknown

    var title: String {
        switch self {
        case .ready: return "已连接"
        case .unauthorized: return "等待授权"
        case .offline: return "设备离线"
        case .unknown: return "未知状态"
        }
    }

    var symbolName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .unauthorized: return "lock.fill"
        case .offline: return "wifi.slash"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct AndroidDevice: Identifiable, Hashable, Sendable {
    let serial: String
    let model: String?
    let product: String?
    let transport: String
    let state: DeviceConnectionState
    let adbSocket: String?
    var hardwareSerial: String? = nil
    /// Keeps an existing session/selection key stable if hardware identity is
    /// learned after a Wi-Fi route first appears. Never used as an ADB target.
    var sessionIdentity: String? = nil

    var id: String {
        // The ADB daemon is a route, not a second phone. Keep selection and
        // process ownership stable when discovery finds another route.
        sessionIdentity ?? hardwareSerial ?? serial
    }

    var isWireless: Bool { transport == "Wi-Fi" }

    var displayName: String {
        let cleanedModel = model?.replacingOccurrences(of: "_", with: " ")
        return cleanedModel?.isEmpty == false ? cleanedModel! : serial
    }

    var detailText: String {
        let socketLabel = adbSocket.map { "ADB \($0)" } ?? "ADB 5037"
        return "\(transport) · \(socketLabel) · \(state.title)"
    }

    var logLabel: String {
        displayName == serial ? serial : "\(displayName) · \(serial)"
    }
}
