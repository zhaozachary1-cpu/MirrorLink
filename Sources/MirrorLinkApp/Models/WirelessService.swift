import Foundation

enum WirelessServiceKind: String, Sendable {
    case pairing = "_adb-tls-pairing._tcp"
    case connection = "_adb-tls-connect._tcp"
}

struct WirelessService: Identifiable, Hashable, Sendable {
    let name: String
    let kind: WirelessServiceKind
    let endpoint: WirelessEndpoint

    var id: String { "\(name)|\(kind.rawValue)|\(endpoint.address)" }
    var adbSerial: String { "\(name).\(kind.rawValue)" }

    /// Presentation only: never use a Bonjour advertisement or a cached label
    /// as authorization, a session identity, or an ADB target. No connection is
    /// opened merely to obtain a name for an unselected nearby phone.
    func deviceName(knownHardwareNames: [String: String], connectedDevices: [AndroidDevice]) -> String? {
        guard kind == .connection else { return nil }
        let hardware = advertisedHardwareSerial
        let matches = connectedDevices.filter { device in
            guard device.state == .ready else { return false }
            let aliases = [adbSerial, adbSerial + ".", adbSerial + ".local", adbSerial + ".local."]
            if device.isWireless && aliases.contains(device.serial) { return true }
            let serial = device.hardwareSerial ?? (device.isWireless ? nil : device.serial)
            return hardware != nil && serial == hardware
        }
        // Prefer current complete metadata, retaining a previously read brand
        // when a temporary getprop failure leaves only the model available.
        let completeNames = Set(matches.filter { $0.brand != nil && $0.model != nil }.map(\.displayName))
        if completeNames.count == 1 { return completeNames.first }
        if let hardware, let saved = Self.label(knownHardwareNames[hardware]) { return saved }
        let names = Set(matches.compactMap { $0.displayName == $0.serial ? nil : Self.label($0.displayName) })
        return names.count == 1 ? names.first : nil
    }

    /// AOSP's adb-<full serial>-<six alphanumerics> format. Match the complete
    /// serial (including embedded hyphens); never guess from IP, model, prefix,
    /// or list order. Nonstandard/OEM names simply have no cached display name.
    private var advertisedHardwareSerial: String? {
        guard name.hasPrefix("adb-"), name.utf8.count <= 139 else { return nil }
        let parts = name.dropFirst(4)
        guard parts.count > 7, parts.suffix(7).first == "-" else { return nil }
        let suffix = parts.suffix(6)
        guard suffix.utf8.count == 6, suffix.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }) else { return nil }
        let serial = String(parts.dropLast(7))
        guard serial.utf8.count <= 128, serial.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }) else { return nil }
        return serial
    }

    private static func label(_ value: String?) -> String? {
        guard let value else { return nil }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 321,
              !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return label
    }

    static func merging(_ services: [WirelessService]) -> [WirelessService] {
        var seen = Set<String>()
        return services.filter { seen.insert($0.id).inserted }.sorted {
            $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}

enum ADBMDNSParser {
    static func parse(_ output: String) -> [WirelessService] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3,
                  let kind = WirelessServiceKind(rawValue: fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "."))),
                  let endpoint = try? WirelessEndpoint(fields[2]) else { return nil }
            let service = WirelessService(name: fields[0], kind: kind, endpoint: endpoint)
            return seen.insert(service.id).inserted ? service : nil
        }.sorted { $0.endpoint.address.localizedStandardCompare($1.endpoint.address) == .orderedAscending }
    }
}
