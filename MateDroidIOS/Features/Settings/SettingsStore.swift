import Foundation

public protocol SettingsStoring: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async
}

public actor UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "appSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings()
        }
        guard var settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        let previousVersion = settings.formatPreferencesVersion
        settings.migrateFormattingPreferences()
        if settings.formatPreferencesVersion != previousVersion,
           let migratedData = try? encoder.encode(settings) {
            defaults.set(migratedData, forKey: key)
        }
        return settings
    }

    public func save(_ settings: AppSettings) async {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
