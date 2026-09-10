import Foundation

public struct AppEnvironment: Sendable {
    public let buildLabel: String
    public let settingsStore: any SettingsStoring
    public let secretStore: any SecretStoring
    public let databaseProvider: any AppDatabaseProviding
    public let notificationService: any AppNotificationServicing

    public init(
        buildLabel: String,
        settingsStore: any SettingsStoring = UserDefaultsSettingsStore(),
        secretStore: any SecretStoring = KeychainStore(),
        databaseProvider: (any AppDatabaseProviding)? = nil,
        notificationService: (any AppNotificationServicing)? = nil
    ) {
        self.buildLabel = buildLabel
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.databaseProvider = databaseProvider ?? LiveAppDatabaseProvider(settingsStore: settingsStore)
        self.notificationService = notificationService ?? SettingsBackedNotificationService(settingsStore: settingsStore)
    }

    public static let live = AppEnvironment(buildLabel: "production")
}
