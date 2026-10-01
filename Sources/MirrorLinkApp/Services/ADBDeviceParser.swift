import Foundation

enum ADBDeviceParser {
    static func parse(_ output: String, adbSocket: String?) -> [AndroidDevice] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let values = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard values.count >= 2,
                      let state = DeviceConnectionState(rawValue: String(values[1])) else { return nil }

                let serial = String(values[0])
                // Unauthorized USB rows often omit all metadata. TCP and emulators are
                // intentionally excluded from the USB-only first release.
                guard !serial.contains(":"), !serial.hasPrefix("emulator-"),
                      !serial.contains("_adb-tls-") else { return nil }
                var metadata: [String: String] = [:]
                for token in values.dropFirst(2) {
                    let pair = token.split(separator: ":", maxSplits: 1).map(String.init)
                    if pair.count == 2 { metadata[pair[0]] = pair[1] }
                }

                return AndroidDevice(
                    serial: serial,
                    model: metadata["model"],
                    product: metadata["product"],
                    transport: "USB",
                    state: state,
                    adbSocket: adbSocket
                )
            }
    }
}
