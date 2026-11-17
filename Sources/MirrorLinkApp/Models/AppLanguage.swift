import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "MirrorLinkLanguage"
    var id: String { rawValue }

    // Keep each choice readable even when the user selected an unfamiliar language.
    var nativeDisplayName: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    static func restored(from value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .system
    }

    func resolved(preferredLanguages: [String]) -> Self {
        guard self == .system else { return self }
        // Match the first supported language in the user's ordered preferences.
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if code == "zh" || code.hasPrefix("zh-") { return .simplifiedChinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    static var systemLanguages: [String] {
        // Read the global domain, not this app's explicit AppleLanguages override.
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }
}
