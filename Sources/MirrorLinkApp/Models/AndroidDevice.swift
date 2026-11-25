import Foundation

enum DeviceConnectionState: String, CaseIterable, Sendable {
    case ready = "device"
    case unauthorized
    case offline
    case unknown

    var title: String {
        switch self {
        case .ready: return L10n.tr("已连接")
        case .unauthorized: return L10n.tr("等待授权")
        case .offline: return L10n.tr("设备离线")
        case .unknown: return L10n.tr("未知状态")
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
    var brand: String? = nil

    var id: String {
        // The ADB daemon is a route, not a second phone. Keep selection and
        // process ownership stable when discovery finds another route.
        sessionIdentity ?? hardwareSerial ?? serial
    }

    var isWireless: Bool { transport == "Wi-Fi" }

    var displayName: String {
        let model = Self.productLabel(model?.replacingOccurrences(of: "_", with: " "))
        let brand = Self.productLabel(brand)
        guard let model else { return brand ?? serial }
        guard let brand else { return model }
        if model.caseInsensitiveCompare(brand) == .orderedSame
            || model.lowercased().hasPrefix(brand.lowercased() + " ") { return model }
        return "\(brand) \(model)"
    }

    /// Two fixed getprop outputs: Android's brand, followed by manufacturer.
    /// Display metadata never participates in routing or authenticated identity.
    static let brandQuery = "getprop ro.product.brand; getprop ro.product.manufacturer"

    static func brand(fromProperties output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        guard (2...3).contains(lines.count), lines.count != 3 || lines[2].isEmpty else { return nil }
        let value = productLabel(lines[0]) ?? productLabel(lines[1])
        guard let value else { return nil }
        let names = ["vivo": "vivo", "oppo": "OPPO", "realme": "realme", "oneplus": "OnePlus",
                     "google": "Google", "samsung": "Samsung", "xiaomi": "Xiaomi", "redmi": "Redmi",
                     "honor": "HONOR", "huawei": "HUAWEI", "motorola": "Motorola", "sony": "Sony"]
        return names[value.lowercased()] ?? value
    }

    private static func productLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 160,
              !["unknown", "null", "none"].contains(label.lowercased()),
              !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return label
    }

    var detailText: String {
        let socketLabel = adbSocket.map { "ADB \($0)" } ?? "ADB 5037"
        return "\(transport) · \(socketLabel) · \(state.title)"
    }

    var logLabel: String {
        displayName == serial ? serial : "\(displayName) · \(serial)"
    }
}
