import Foundation

public protocol AchievementsAPIProviding: Sendable {
    func achievements(carId: Int) async -> APIResult<AchievementsPayload>
}

extension TeslamateAPI: AchievementsAPIProviding {}

public struct SettingsBackedAchievementsAPI: AchievementsAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }

    public func achievements(carId: Int) async -> APIResult<AchievementsPayload> {
        await factory.request { await $0.achievements(carId: carId) }
    }
}
