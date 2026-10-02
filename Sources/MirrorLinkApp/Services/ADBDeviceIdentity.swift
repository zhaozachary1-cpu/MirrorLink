import Foundation

enum ADBDeviceIdentity {
    static func hardwareSerial(from result: ProcessResult) -> String? {
        guard result.succeeded else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 128,
              !["unknown", "null", "none", "0"].contains(value.lowercased()),
              value.utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                      || $0 == 45 || $0 == 46 || $0 == 95
              }) else { return nil }
        return value
    }

    /// Prefer a ready Wi-Fi route, but never swap the process of an active session.
    static func preferred(_ first: AndroidDevice, _ second: AndroidDevice) -> AndroidDevice {
        func rank(_ state: DeviceConnectionState) -> Int {
            switch state {
            case .ready: return 0
            case .unauthorized: return 1
            case .offline: return 2
            case .unknown: return 3
            }
        }
        if rank(first.state) != rank(second.state) { return rank(first.state) < rank(second.state) ? first : second }
        if first.isWireless != second.isWireless { return first.isWireless ? first : second }
        return first
    }
}
