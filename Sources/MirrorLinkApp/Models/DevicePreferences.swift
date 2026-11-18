import Foundation

extension MirrorQualityProfile: Codable {}

struct DevicePreferences: Codable, Equatable {
    var nickname = ""
    var favorite = false
    var qualityProfile: MirrorQualityProfile?
    var audioEnabled = true
    var autoReconnect = false
    var presentationMode = false
    var alwaysOnTop = false
    var fullscreen = false

    var normalized: Self {
        var value = self
        value.nickname = String(nickname.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
        return value
    }

    /// Only authenticated hardware identities are persisted. An IP:port or
    /// an unverified mDNS name is a route, never a reusable device identity.
    static func identity(for device: AndroidDevice) -> String? {
        guard device.state == .ready else { return nil }
        let raw = device.hardwareSerial ?? (device.isWireless ? nil : device.serial)
        guard let raw, !raw.isEmpty, raw != "unknown", raw.count <= 256,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return "hardware:\(raw)"
    }
}

struct KnownDevice: Identifiable, Codable, Equatable {
    let id: String
    var model: String
    var preferences: DevicePreferences
    var lastSeen: Date

    var displayName: String { preferences.nickname.isEmpty ? (model.isEmpty ? L10n.tr("Android 手机") : model) : preferences.nickname }
}
