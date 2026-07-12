import Foundation

public protocol DriveAPIProviding: Sendable {
    func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]>
    func driveDetail(carId: Int, driveId: Int) async -> APIResult<DriveDetail>
    func carStatus(carId: Int) async -> APIResult<CarStatusPayload>
}

extension TeslamateAPI: DriveAPIProviding {}

public protocol DriveWeatherServicing: Sendable {
    func weatherAlongDrive(positions: [WeatherRoutePosition], totalDistanceKm: Double) async -> [WeatherPoint]
}

extension WeatherService: DriveWeatherServicing {}

public struct SettingsBackedDriveAPI: DriveAPIProviding {
    private let apiFactory: SettingsBackedTeslamateAPIFactory

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        self.apiFactory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }

    public func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]> {
        await apiFactory.request { api in
            await api.drives(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show)
        }
    }

    public func driveDetail(carId: Int, driveId: Int) async -> APIResult<DriveDetail> {
        await apiFactory.request { api in
            await api.driveDetail(carId: carId, driveId: driveId)
        }
    }

    public func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        await apiFactory.request { api in
            await api.carStatus(carId: carId)
        }
    }
}
