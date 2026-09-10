import Foundation

public protocol AnalyticsAPIProviding: Sendable {
    func serverStats(carId: Int) async -> APIResult<TeslaMateServerStatsResponse>
    func batteryHealth(carId: Int) async -> APIResult<BatteryHealth>
    func batteryHistory(carId: Int) async -> APIResult<BatteryHistoryData>
    func updates(carId: Int, page: Int?, show: Int?) async -> APIResult<[UpdateData]>
    func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]>
    func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]>
    func driveDetail(carId: Int, driveId: Int) async -> APIResult<DriveDetail>
    func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<ChargeDetail>
    func carStatus(carId: Int) async -> APIResult<CarStatusPayload>
}

public extension AnalyticsAPIProviding {
    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> { .failure(.httpStatus(404)) }
    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> {
        .failure(.httpStatus(404))
    }
}

extension TeslamateAPI: AnalyticsAPIProviding {}

public struct SettingsBackedAnalyticsAPI: AnalyticsAPIProviding {
    private let apiFactory: SettingsBackedTeslamateAPIFactory

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        networkPolicy: APIRequestNetworkPolicy = .online
    ) {
        self.apiFactory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: secretStore,
            networkPolicy: networkPolicy
        )
    }

    public func batteryHealth(carId: Int) async -> APIResult<BatteryHealth> {
        await apiFactory.request { api in
            await api.batteryHealth(carId: carId)
        }
    }

    public func batteryHistory(carId: Int) async -> APIResult<BatteryHistoryData> {
        await apiFactory.request { api in await api.batteryHistory(carId: carId) }
    }

    public func serverStats(carId: Int) async -> APIResult<TeslaMateServerStatsResponse> {
        await apiFactory.request { api in
            await api.serverStats(carId: carId)
        }
    }

    public func updates(carId: Int, page: Int?, show: Int?) async -> APIResult<[UpdateData]> {
        await apiFactory.request { api in
            await api.updates(carId: carId, page: page, show: show)
        }
    }

    public func drives(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[DriveData]> {
        await apiFactory.request { api in
            await api.drives(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show)
        }
    }

    public func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]> {
        await apiFactory.request { api in
            await api.charges(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show)
        }
    }

    public func driveDetail(carId: Int, driveId: Int) async -> APIResult<DriveDetail> {
        await apiFactory.request { api in
            await api.driveDetail(carId: carId, driveId: driveId)
        }
    }

    public func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<ChargeDetail> {
        await apiFactory.request { api in
            await api.chargeDetail(carId: carId, chargeId: chargeId)
        }
    }

    public func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        await apiFactory.request { api in
            await api.carStatus(carId: carId)
        }
    }
}

extension APIError {
    var analyticsMessage: String {
        switch self {
        case .serverNotConfigured:
            return "Configure your TeslaMate server before loading analytics."
        case let .invalidURL(url):
            return "Invalid TeslaMate URL: \(url)"
        case let .httpStatus(status):
            return "TeslaMate returned HTTP \(status)."
        case let .sslCertificate(message):
            return "SSL certificate error: \(message)"
        case let .invalidResponse(message):
            return "Invalid TeslaMate response: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case .cancelled:
            return "Request cancelled."
        case .emptyBody:
            return "TeslaMate returned no analytics data."
        }
    }
}
