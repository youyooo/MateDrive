import Foundation

public protocol EnvironmentHistoryAPIProviding: Sendable {
    func environmentHistory(carId: Int, range: String, grain: String) async -> APIResult<EnvironmentHistoryResponse>
}

extension TeslamateAPI: EnvironmentHistoryAPIProviding {}

public struct SettingsBackedEnvironmentHistoryAPI: EnvironmentHistoryAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        networkPolicy: APIRequestNetworkPolicy = .online
    ) {
        factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: secretStore,
            networkPolicy: networkPolicy
        )
    }

    public func environmentHistory(carId: Int, range: String, grain: String) async -> APIResult<EnvironmentHistoryResponse> {
        await factory.request { await $0.environmentHistory(carId: carId, range: range, grain: grain) }
    }
}
