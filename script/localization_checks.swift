import Foundation

@main
struct LocalizationChecks {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let resources = root.appendingPathComponent("Sources/MirrorLinkApp/Resources/Localizations")
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        func catalog(_ language: String, _ table: String = "Localizable") throws -> [String: String] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(language).lproj/\(table).strings"))
            return try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
        }
        let en = try catalog("en")
        let zh = try catalog("zh-Hans")
        check(en.count > 200 && Set(en.keys) == Set(zh.keys), "both catalogs contain the same complete set of keys")
        let placeholder = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?@"#)
        for (key, translation) in en {
            let matches = placeholder.matches(in: key, range: NSRange(key.startIndex..., in: key))
            let translatedMatches = placeholder.matches(in: translation, range: NSRange(translation.startIndex..., in: translation))
            check(matches.count == translatedMatches.count, "placeholder parity: \(key)")
            check(zh[key] == key, "Chinese source is preserved: \(key)")
            let args = matches.indices.map { "VALUE\($0) 100% %@ 中文" }
            for language in [AppLanguage.english, .simplifiedChinese] {
                let text = L10n.resolve(key, arguments: args, language: language)
                check(!text.isEmpty || key.isEmpty, "bundled translation resolves: \(key)")
                for arg in args { check(text.contains(arg), "format values remain literal and intact") }
            }
        }
        for language in ["en", "zh-Hans"] {
            let info = try catalog(language, "InfoPlist")
            check(info["CFBundleDisplayName"] != nil && info["NSLocalNetworkUsageDescription"] != nil, "localized system metadata")
        }

        // Fail if a new literal lookup lacks a catalog entry. Dynamic keys are
        // enumerated explicitly below so they cannot silently fall back.
        let lookup = try NSRegularExpression(pattern: #"L10n\.(?:tr|message)\(\"((?:[^\"\\]|\\.)*)\""#)
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Sources/MirrorLinkApp"), includingPropertiesForKeys: nil)!
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in lookup.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let literal = String(source[Range(match.range(at: 1), in: source)!])
                let key = try JSONSerialization.jsonObject(with: Data(("\"" + literal + "\"").utf8), options: .fragmentsAllowed) as! String
                check(en[key] != nil, "missing translation in \(file.lastPathComponent): \(key)")
            }
        }
        for key in ["首次配对", "连接手机", "扫码配对", "发现手机", "手动连接", "%@ 台正在投屏", "%@ 台正在启动", "%@ 台正在停止"] {
            check(en[key] != nil, "dynamic key is translated: \(key)")
        }

        check(AppLanguage.restored(from: nil) == .system, "first launch follows system")
        check(AppLanguage.restored(from: "future-language") == .system, "invalid preference falls back safely")
        check(AppLanguage.system.resolved(preferredLanguages: ["zh_CN", "en-US"]) == .simplifiedChinese, "Chinese region matching")
        check(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW"]) == .simplifiedChinese, "Chinese variants use supported Chinese")
        check(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]) == .english, "system language order is respected")
        check(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans"]) == .simplifiedChinese, "first supported language wins")
        check(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .english, "unsupported languages fall back to English")
        check(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english, "explicit language beats system")

        let domain = "com.mirrorlink.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); L10n.setLanguage(.simplifiedChinese) }
        let globalBefore = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?
        defaults.set("nativeSmooth", forKey: MirrorQualityProfile.preferenceKey)
        let settings = LanguageStore(defaults: defaults, preferredLanguages: { ["zh-Hans"] })
        check(settings.selection == .system && L10n.tr("镜连") == "镜连", "system default displays Chinese")
        let message = L10n.message("已选择 %@ 台设备", "2")
        let chineseMessage = message.resolved
        settings.selection = .english
        check(defaults.string(forKey: AppLanguage.preferenceKey) == "en", "selection persists")
        check(defaults.stringArray(forKey: "AppleLanguages") == ["en"], "native language override is app scoped")
        check(settings.effectiveLocale.identifier == "en" && L10n.tr("镜连") == "MirrorLink", "live English lookup")
        check(message.resolved != chineseMessage && message.resolved.contains("2"), "existing operation message re-resolves")
        check(MirrorSessionState.mirroring.title == en["正在投屏"], "state labels change language")
        check(MirrorQualityProfile.nativeClarity.title == en["原生超清（推荐）"], "quality labels change language")
        var video = MirrorVideoStatus(profile: .nativeClarity, isWireless: true)
        video.noteEncoderConstraint()
        let englishWarning = video.warning
        settings.selection = .simplifiedChinese
        check(video.warning != englishWarning && video.warning == zh["手机编码器调整了画面参数，请以实际画面尺寸为准；若清晰度不足，可重新投屏或改用兼容档。"], "existing video warning re-resolves")
        let restored = LanguageStore(defaults: defaults, preferredLanguages: { ["en"] })
        check(restored.selection == .simplifiedChinese, "selection survives a new store")
        restored.selection = .system
        check(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil && L10n.tr("镜连") == "MirrorLink", "system choice removes only app override")
        check(defaults.string(forKey: MirrorQualityProfile.preferenceKey) == "nativeSmooth", "language never changes quality preference")
        check(globalBefore == UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) as NSDictionary?, "system preferences remain untouched")
        check(LocalizedMessage.verbatim("ADB: 100% %@ 原始输出").resolved == "ADB: 100% %@ 原始输出", "upstream diagnostics are never interpreted as format strings")
        check(L10n.tr("unknown literal %@") == "unknown literal %@", "unknown untranslated text is safe without args")
        let date = L10n.formattedDate(Date(timeIntervalSince1970: 0))
        check(date.range(of: #"^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$"#, options: .regularExpression) != nil, "dates retain DD/MM/YYYY and 24-hour time")
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            L10n.setLanguage(index.isMultiple(of: 2) ? .english : .simplifiedChinese)
            precondition(["MirrorLink", "镜连"].contains(L10n.tr("镜连")))
        }
        check(true, "concurrent service lookups and language changes are safe")
        print("MirrorLink localization checks passed (\(checks) assertions, \(en.count) bilingual messages)")
    }
}
