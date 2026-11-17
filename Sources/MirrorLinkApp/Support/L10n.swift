import Foundation

/// Stores a message's identity so visible operation state can change language
/// without repeating an operation. Raw tool output remains verbatim.
struct LocalizedMessage: Equatable, Sendable {
    let key: String
    let arguments: [String]
    private let isVerbatim: Bool

    init(key: String, arguments: [String] = []) {
        self.key = key
        self.arguments = arguments
        self.isVerbatim = false
    }

    private init(verbatim text: String) {
        key = text
        arguments = []
        isVerbatim = true
    }

    static func verbatim(_ text: String) -> Self { Self(verbatim: text) }
    var resolved: String { isVerbatim ? key : L10n.resolve(key, arguments: arguments) }
    var localized: String { resolved }
}

enum L10n {
    private static let state = LanguageState()

    static var language: AppLanguage { state.language }

    static func setLanguage(_ language: AppLanguage) {
        state.language = language.resolved(preferredLanguages: AppLanguage.systemLanguages)
    }

    static func tr(_ key: String, _ arguments: String...) -> String {
        resolve(key, arguments: arguments)
    }

    static func message(_ key: String, _ arguments: String...) -> LocalizedMessage {
        LocalizedMessage(key: key, arguments: arguments)
    }

    static func resolve(_ key: String, arguments: [String], language: AppLanguage? = nil) -> String {
        let effective = language ?? self.language
        let template = localizedBundle(for: effective)?.localizedString(forKey: key, value: key, table: nil) ?? key
        guard !arguments.isEmpty else { return template }
        // Catalogs use only %@ (optionally positional). Values never become formats.
        return String(format: template, locale: Locale(identifier: effective.rawValue), arguments: arguments)
    }

    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }

    static func localizedBundle(for language: AppLanguage) -> Bundle? {
        let code = language == .simplifiedChinese ? "zh-Hans" : "en"
        return bundles[code]
    }

    private static let bundles: [String: Bundle] = {
        let root: URL
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("en.lproj/Localizable.strings").path) {
            root = resources
        } else {
            #if SWIFT_PACKAGE
            root = Bundle.module.resourceURL!
            #else
            // Standalone checks explicitly supply the fixture resource directory.
            guard let path = ProcessInfo.processInfo.environment["MIRRORLINK_LOCALIZATION_ROOT"] else { return [:] }
            root = URL(fileURLWithPath: path, isDirectory: true)
            #endif
        }
        return ["en", "zh-Hans"].reduce(into: [:]) { result, code in
            result[code] = Bundle(url: root.appendingPathComponent("\(code).lproj", isDirectory: true))
        }
    }()

    // Services may format errors off the main actor. Guard only the language
    // value; immutable resource bundles are shared without actor coupling.
    private final class LanguageState: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AppLanguage

        init() {
            #if !SWIFT_PACKAGE
            if let testLanguage = ProcessInfo.processInfo.environment["MIRRORLINK_TEST_LANGUAGE"] {
                value = AppLanguage.restored(from: testLanguage).resolved(preferredLanguages: ["zh-Hans"])
                return
            }
            #endif
            value = AppLanguage.restored(from: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
                .resolved(preferredLanguages: AppLanguage.systemLanguages)
        }

        var language: AppLanguage {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); defer { lock.unlock() }; value = newValue }
        }
    }
}
