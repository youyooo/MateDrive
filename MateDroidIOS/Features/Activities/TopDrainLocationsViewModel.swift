import Combine
import Foundation

public protocol TopDrainLocationsAPIProviding: Sendable {
    func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse>
}

extension TeslamateAPI: TopDrainLocationsAPIProviding {}

public struct SettingsBackedTopDrainLocationsAPI: TopDrainLocationsAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory
    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }
    public func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse> {
        await factory.request { await $0.topDrainLocations(carId: carId) }
    }
}

public struct TopDrainLocationsState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var locations: [TopDrainLocation] = []
    public var units: TeslaMateServerStatsUnits?
    public init() {}
}

@MainActor
public final class TopDrainLocationsViewModel: ObservableObject {
    @Published public private(set) var state: TopDrainLocationsState
    private let api: any TopDrainLocationsAPIProviding

    public init(api: any TopDrainLocationsAPIProviding, initialState: TopDrainLocationsState = TopDrainLocationsState()) {
        self.api = api
        state = initialState
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        switch await api.topDrainLocations(carId: carId) {
        case let .success(response):
            state.locations = response.locations
                .filter { GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil }
                .sorted { ($0.totalRangeLossKm ?? -.infinity) > ($1.totalRangeLossKm ?? -.infinity) }
            state.units = response.units
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }
}
