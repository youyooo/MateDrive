import Foundation

public protocol DriveInsightsAPIProviding: Sendable {
    func driveInsights(carId: Int) async -> APIResult<TeslaMateDriveInsightsData>
    func activities(carId: Int, page: Int, show: Int) async -> APIResult<TeslaMateActivitiesResponse>
    func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]>
}

extension TeslamateAPI: DriveInsightsAPIProviding {}

public struct SettingsBackedDriveInsightsAPI: DriveInsightsAPIProviding {
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

    public func driveInsights(carId: Int) async -> APIResult<TeslaMateDriveInsightsData> {
        await factory.request { await $0.driveInsights(carId: carId) }
    }

    public func activities(carId: Int, page: Int, show: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        await factory.request { await $0.activities(carId: carId, page: page, show: show) }
    }

    public func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]> {
        await factory.request { await $0.drives(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show) }
    }
}
