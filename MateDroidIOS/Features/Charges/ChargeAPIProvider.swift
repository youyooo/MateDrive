import Foundation

public protocol ChargeCostUpdating: Sendable {
    func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void>
}

public protocol ChargeAPIProviding: ChargeCostUpdating {
    func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]>
    func currentCharge(carId: Int) async -> APIResult<CurrentChargeOutcome>
    func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<ChargeDetail>
    func carStatus(carId: Int) async -> APIResult<CarStatusPayload>
    func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void>
}

public extension ChargeAPIProviding {
    func updateChargeCost(chargeId _: Int, cost _: Double?) async -> APIResult<Void> {
        .failure(.httpStatus(404))
    }
}

extension TeslamateAPI: ChargeAPIProviding {}

public struct SettingsBackedChargeAPI: ChargeAPIProviding {
    private let apiFactory: SettingsBackedTeslamateAPIFactory

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        self.apiFactory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }

    public func charges(carId: Int, startDate: String?, endDate: String?, page: Int?, show: Int?) async -> APIResult<[ChargeData]> {
        await apiFactory.request { api in
            await api.charges(carId: carId, startDate: startDate, endDate: endDate, page: page, show: show)
        }
    }

    public func currentCharge(carId: Int) async -> APIResult<CurrentChargeOutcome> {
        await apiFactory.request { api in
            await api.currentCharge(carId: carId)
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

    public func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void> {
        await apiFactory.request { api in
            await api.updateChargeCost(chargeId: chargeId, cost: cost)
        }
    }
}
