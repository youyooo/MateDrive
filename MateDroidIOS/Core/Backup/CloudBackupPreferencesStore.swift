import Foundation

public protocol CloudBackupPreferencesStoring: Sendable {
    func load() async -> CloudBackupPreferences
    func save(_ preferences: CloudBackupPreferences) async
}

public final class UserDefaultsCloudBackupPreferencesStore: CloudBackupPreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "cloudBackupPreferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> CloudBackupPreferences {
        lock.withLock {
            guard let data = defaults.data(forKey: key),
                  let preferences = try? decoder.decode(CloudBackupPreferences.self, from: data)
            else { return CloudBackupPreferences() }
            return preferences
        }
    }

    public func save(_ preferences: CloudBackupPreferences) async {
        lock.withLock {
            guard let data = try? encoder.encode(preferences) else { return }
            defaults.set(data, forKey: key)
        }
    }
}
