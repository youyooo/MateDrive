import Foundation

public protocol SettingsStoring: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async
    func saveThrowing(_ settings: AppSettings) async throws
}

public protocol AtomicSettingsUpdating: Sendable {
    @discardableResult
    func updateAtomically(
        _ transform: @Sendable (AppSettings) -> AppSettings
    ) async throws -> AppSettings
}

public extension SettingsStoring {
    func saveThrowing(_ settings: AppSettings) async throws {
        await save(settings)
    }
}

public actor UserDefaultsSettingsStore: SettingsStoring, AtomicSettingsUpdating {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(
        defaults: UserDefaults = .standard,
        key: String = "appSettings"
    ) {
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
            guard defaults.data(forKey: key) == data else {
                return currentSettings()
            }
            defaults.set(migratedData, forKey: key)
        }
        return settings
    }

    public func save(_ settings: AppSettings) async {
        try? saveEncoded(settings)
    }

    public func saveThrowing(_ settings: AppSettings) async throws {
        try saveEncoded(settings)
    }

    public func updateAtomically(
        _ transform: @Sendable (AppSettings) -> AppSettings
    ) async throws -> AppSettings {
        let updated = transform(currentSettings())
        let data = try encoder.encode(updated)
        defaults.set(data, forKey: key)
        return updated
    }

    private func currentSettings() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    private func saveEncoded(_ settings: AppSettings) throws {
        defaults.set(try encoder.encode(settings), forKey: key)
    }
}
