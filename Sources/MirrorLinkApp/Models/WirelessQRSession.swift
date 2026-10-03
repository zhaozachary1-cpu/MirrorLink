import Foundation
import Security

/// Android's native wireless-debugging QR format. No external QR service,
/// clipboard, preferences or logging: these credentials exist only in memory.
struct WirelessQRSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let serviceName: String
    let password: String
    let expiresAt: Date

    init(now: Date = Date(), lifetime: TimeInterval = 120) throws {
        func randomHex(count: Int) throws -> String {
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
                throw WirelessConnectionError.failed("无法安全生成二维码，请重试。")
            }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        serviceName = "studio-" + (try randomHex(count: 12))
        password = try randomHex(count: 16)
        expiresAt = now.addingTimeInterval(lifetime)
    }

    var payload: String { "WIFI:T:ADB;S:\(serviceName);P:\(password);;" }
    var description: String { "WirelessQRSession(<redacted>)" }
    var debugDescription: String { description }

    func matches(_ service: WirelessService) -> Bool {
        service.kind == .pairing && service.name == serviceName
    }
}

/// GUID returned by ADB's authenticated pairing exchange, not an IP heuristic.
struct WirelessPairingIdentity: Equatable, Sendable {
    let guid: String

    init?(output: String, endpoint: WirelessEndpoint) {
        guard let acknowledgement = output.range(of: "Successfully paired to "),
              let start = output.range(of: " [guid=", range: acknowledgement.upperBound..<output.endIndex),
              let end = output[start.upperBound...].firstIndex(of: "]"),
              (try? WirelessEndpoint(String(output[acknowledgement.upperBound..<start.lowerBound]))) == endpoint
        else { return nil }
        let value = String(output[start.upperBound..<end])
        guard !value.isEmpty, value.utf8.count <= 128, value.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        guid = value
    }

    func matches(_ service: WirelessService) -> Bool {
        service.kind == .connection && service.name == guid
    }
}
