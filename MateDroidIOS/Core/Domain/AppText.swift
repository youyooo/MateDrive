import Foundation

public enum AppText {
    public static func localized(
        _ english: String,
        _ chinese: String,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> String {
        switch language {
        case .chinese:
            return chinese
        case .traditionalChinese:
            return localized(english, localeIdentifier: "zh-Hant", bundle: bundle)
        case .english:
            return english
        case .system:
            guard let preferred = Locale.preferredLanguages.first else { return english }
            if usesTraditionalChinese(language: language, preferredLanguage: preferred) {
                return localized(english, localeIdentifier: "zh-Hant", bundle: bundle)
            }
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            if normalized.hasPrefix("zh") { return chinese }
            return localized(english, localeIdentifier: preferred, bundle: bundle)
        case .german, .spanish, .italian, .catalan:
            guard let identifier = language.localeIdentifier else { return english }
            return localized(english, localeIdentifier: identifier, bundle: bundle)
        }
    }

    public static func usesTraditionalChinese(
        language: AppLanguage,
        preferredLanguage: String? = Locale.preferredLanguages.first
    ) -> Bool {
        switch language {
        case .traditionalChinese:
            return true
        case .system:
            let normalized = preferredLanguage?.replacingOccurrences(of: "_", with: "-") ?? ""
            return normalized.hasPrefix("zh-Hant") || normalized.hasPrefix("zh-TW") || normalized.hasPrefix("zh-HK") || normalized.hasPrefix("zh-MO")
        case .english, .chinese, .german, .spanish, .italian, .catalan:
            return false
        }
    }

    private static func localized(_ key: String, localeIdentifier: String, bundle: Bundle) -> String {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let resource = normalized.hasPrefix("zh-Hant") ? "zh-Hant" : (normalized.split(separator: "-").first.map(String.init) ?? normalized)
        guard let path = bundle.path(forResource: resource, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else {
            return key
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}
