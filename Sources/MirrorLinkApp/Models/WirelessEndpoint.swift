import Darwin
import Foundation

/// A numeric address and an explicit port, never a shell fragment or an ADB option.
struct WirelessEndpoint: Hashable, Sendable {
    let host: String
    let port: UInt16

    var address: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    init(_ text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostText: String
        let portText: String
        if value.hasPrefix("["), let end = value.firstIndex(of: "]") {
            hostText = String(value[value.index(after: value.startIndex)..<end])
            let suffix = value[value.index(after: end)...]
            guard suffix.hasPrefix(":") else { throw WirelessConnectionError.invalidEndpoint }
            portText = String(suffix.dropFirst())
        } else {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw WirelessConnectionError.invalidEndpoint }
            hostText = String(parts[0])
            portText = String(parts[1])
        }
        guard !portText.isEmpty, portText.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = UInt16(portText), port > 0 else { throw WirelessConnectionError.invalidEndpoint }

        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        let zoneParts = hostText.split(separator: "%", omittingEmptySubsequences: false)
        guard (1...2).contains(zoneParts.count) else { throw WirelessConnectionError.invalidEndpoint }
        let rawHost = String(zoneParts[0])
        if zoneParts.count == 2 {
            let zone = zoneParts[1]
            guard !zone.isEmpty, zone.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45
            }) else { throw WirelessConnectionError.invalidEndpoint }
        }
        let isV4 = inet_pton(AF_INET, rawHost, &ipv4) == 1
        let isV6 = inet_pton(AF_INET6, rawHost, &ipv6) == 1
        guard (isV4 && zoneParts.count == 1) || isV6 else { throw WirelessConnectionError.invalidEndpoint }
        // Reject unspecified, loopback, multicast and broadcast targets. They are
        // not a phone on the local network (and localhost could target this Mac).
        if isV4 {
            let parts = rawHost.split(separator: ".")
            // Darwin's inet_pton accepts leading zeroes; reject ambiguous input
            // instead of letting another ADB/network parser interpret it differently.
            guard parts.allSatisfy({ $0.count == 1 || $0.first != "0" }) else {
                throw WirelessConnectionError.invalidEndpoint
            }
            let octets = parts.compactMap { Int($0) }
            guard octets.count == 4, octets[0] > 0, octets[0] != 127, octets[0] < 224 else {
                throw WirelessConnectionError.invalidEndpoint
            }
        } else {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            guard bytes.contains(where: { $0 != 0 }),
                  !(bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1),
                  bytes.first != 0xff,
                  !(bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff) else {
                throw WirelessConnectionError.invalidEndpoint
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if isV4 { _ = inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(buffer.count)) }
        else { _ = inet_ntop(AF_INET6, &ipv6, &buffer, socklen_t(buffer.count)) }
        host = String(cString: buffer) + (zoneParts.count == 2 ? "%\(zoneParts[1])" : "")
        self.port = port
    }
}

enum WirelessConnectionError: Error, LocalizedError, Equatable {
    case invalidEndpoint
    case invalidPairingCode
    case toolsMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请输入手机显示的 IP 地址和端口，例如 192.168.1.8:37123。IPv6 使用 [地址]:端口；不能使用本机地址。"
        case .invalidPairingCode: return "配对码应为手机当前显示的 6 位数字。"
        case .toolsMissing: return "应用内置 ADB 不可用，请重新安装完整的镜连应用。"
        case let .failed(message): return message
        }
    }
}
