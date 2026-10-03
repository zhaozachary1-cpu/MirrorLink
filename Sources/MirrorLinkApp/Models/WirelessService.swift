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
