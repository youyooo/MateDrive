import Foundation

public enum AppText {
    private static let traditionalTextCache = TraditionalTextCache()

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
            return traditionalized(chinese)
        case .english:
            return english
        case .system:
            guard let preferred = Locale.preferredLanguages.first else { return english }
            if usesTraditionalChinese(language: language, preferredLanguage: preferred) {
                return traditionalized(chinese)
            }
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            if normalized.hasPrefix("zh") { return chinese }
            return localized(english, localeIdentifier: preferred, bundle: bundle)
        }
    }

    static func traditionalized(_ simplified: String) -> String {
        traditionalTextCache.value(for: simplified)
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
        case .english, .chinese:
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

private final class TraditionalTextCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSString>()
    private let preferredPhrases: [(source: String, replacement: String)] = [
        ("服務器", "伺服器"),
        ("設置", "設定"),
        ("數據", "資料"),
        ("加載", "載入"),
        ("緩存", "快取"),
        ("用戶", "使用者"),
        ("軟件", "軟體"),
        ("網絡", "網路"),
        ("默認", "預設"),
        ("保存", "儲存"),
        ("鑰匙串", "鑰匙圈"),
        ("反饋", "回饋"),
        ("身份", "身分")
    ]

    init() {
        cache.countLimit = 1_024
    }

    func value(for simplified: String) -> String {
        let key = simplified as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }

        var converted = simplified.applyingTransform(
            StringTransform("Simplified-Traditional"),
            reverse: false
        ) ?? simplified
        for phrase in preferredPhrases {
            converted = converted.replacingOccurrences(
                of: phrase.source,
                with: phrase.replacement
            )
        }
        cache.setObject(converted as NSString, forKey: key)
        return converted
    }
}
