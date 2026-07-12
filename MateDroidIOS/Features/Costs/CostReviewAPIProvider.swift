import Foundation

public protocol CostReviewAPIProviding: Sendable {
    func costReview(carId: Int, startDate: Date, endDate: Date) async -> APIResult<CostReviewResponse>
}

extension TeslamateAPI: CostReviewAPIProviding {}

public struct SettingsBackedCostReviewAPI: CostReviewAPIProviding {
    private let apiFactory: SettingsBackedTeslamateAPIFactory

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        apiFactory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }

    public func costReview(carId: Int, startDate: Date, endDate: Date) async -> APIResult<CostReviewResponse> {
        await apiFactory.request { api in
            await api.costReview(carId: carId, startDate: startDate, endDate: endDate)
        }
    }
}
