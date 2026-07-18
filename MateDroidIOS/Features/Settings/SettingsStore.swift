import Foundation

public protocol SettingsStoring: Sendable {
    func load() async -> AppSettings
    func save(_ settings: AppSettings) async
    func saveThrowing(_ settings: AppSettings) async throws
}

public extension SettingsStoring {
    func saveThrowing(_ settings: AppSettings) async throws {
        await save(settings)
    }
}

public actor UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let vehicleImageCatalog: @Sendable () async -> VehicleImageCatalog?

    public init(
        defaults: UserDefaults = .standard,
        key: String = "appSettings",
        vehicleImageCatalog: @escaping @Sendable () async -> VehicleImageCatalog? = {
            await MainActor.run {
                try? BundledVehicleImageCatalogProvider().catalog()
            }
        }
    ) {
        self.defaults = defaults
        self.key = key
        self.vehicleImageCatalog = vehicleImageCatalog
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
        let migratedVehicleImageOverrides: Bool
        if settings.hasLegacyVehicleImageOverrideValues, let catalog = await vehicleImageCatalog() {
            migratedVehicleImageOverrides = settings.migrateLegacyVehicleImageOverrides(catalog: catalog)
        } else {
            migratedVehicleImageOverrides = false
        }
        if settings.formatPreferencesVersion != previousVersion || migratedVehicleImageOverrides,
           let migratedData = try? encoder.encode(settings) {
            guard defaults.data(forKey: key) == data else {
                return currentSettings()
            }
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

    private func currentSettings() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }
}
