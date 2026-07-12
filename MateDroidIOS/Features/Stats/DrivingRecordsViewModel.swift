import Combine
import Foundation

public protocol DrivingRecordsAPIProviding: Sendable {
    func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse>
}

extension TeslamateAPI: DrivingRecordsAPIProviding {}

public struct SettingsBackedDrivingRecordsAPI: DrivingRecordsAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory
    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }
    public func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse> {
        await factory.request { await $0.statsExtremes(carId: carId) }
    }
}

public struct DrivingRecordsState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var records: [StatsExtreme] = []
    public var units: TeslaMateServerStatsUnits?
    public init() {}
}

@MainActor
public final class DrivingRecordsViewModel: ObservableObject {
    @Published public private(set) var state: DrivingRecordsState
    private let api: any DrivingRecordsAPIProviding

    public init(api: any DrivingRecordsAPIProviding, initialState: DrivingRecordsState = DrivingRecordsState()) {
        self.api = api
        state = initialState
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        switch await api.statsExtremes(carId: carId) {
        case let .success(response):
            state.records = response.extremes
            state.units = response.units
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }
}
