import Combine
import Foundation

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published var selection: AppLanguage {
        didSet {
            guard oldValue != selection else { return }
            defaults.set(selection.rawValue, forKey: AppLanguage.preferenceKey)
            applySelection()
        }
    }

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var localeObserver: NSObjectProtocol?
    var effectiveLocale: Locale {
        Locale(identifier: selection.resolved(preferredLanguages: preferredLanguages()).rawValue)
    }

    init(defaults: UserDefaults = .standard,
         preferredLanguages: @escaping () -> [String] = { AppLanguage.systemLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        selection = AppLanguage.restored(from: defaults.string(forKey: AppLanguage.preferenceKey))
        applySelection()
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.selection == .system else { return }
                self.objectWillChange.send()
                self.applySelection()
            }
        }
    }

    deinit {
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
    }

    private func applySelection() {
        L10n.setLanguage(selection.resolved(preferredLanguages: preferredLanguages()))
        // This affects only MirrorLink's preferences. Native system menus and
        // Sparkle read the process language at the next launch.
        if selection == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([selection.rawValue], forKey: "AppleLanguages")
        }
    }
}
