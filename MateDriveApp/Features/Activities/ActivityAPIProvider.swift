import Foundation

public protocol ActivityAPIProviding: Sendable {
    func activities(carId: Int, page: Int, show: Int) async -> APIResult<TeslaMateActivitiesResponse>
    func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]>
    func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]>
    func standbyDrain(carId: Int, latitude: Double, longitude: Double) async -> APIResult<StandbyDrainResponse>
}

extension TeslamateAPI: ActivityAPIProviding {}

public struct SettingsBackedActivityAPI: ActivityAPIProviding {
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

    public func activities(carId: Int, page: Int, show: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        await factory.request { await $0.activities(carId: carId, page: page, show: show) }
    }

    public func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]> {
        await factory.request { await $0.drives(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show) }
    }

    public func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]> {
        await factory.request { await $0.charges(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show) }
    }

    public func standbyDrain(carId: Int, latitude: Double, longitude: Double) async -> APIResult<StandbyDrainResponse> {
        await factory.request { await $0.standbyDrain(carId: carId, latitude: latitude, longitude: longitude) }
    }
}
