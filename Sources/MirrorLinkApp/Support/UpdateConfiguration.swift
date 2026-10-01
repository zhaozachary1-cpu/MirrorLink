import Foundation

enum UpdateConfiguration {
    static let customFeedKey = "MirrorLinkCustomUpdateFeed"

    // The download source may move; the trusted signing key must not come from it.
    static func validatedFeedURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let url = parts.url else { return nil }
        return url
    }

    static func hasValidPublicKey(_ key: String?) -> Bool {
        guard let key, let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    static func effectiveFeed(bundled: String?, custom: String?) -> URL? {
        // A release's sealed configuration takes precedence over local settings.
        if let bundled, !bundled.isEmpty { return validatedFeedURL(bundled) }
        return custom.flatMap(validatedFeedURL)
    }
}
