import Combine
import Foundation

public protocol TopDrainLocationsAPIProviding: Sendable {
    func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse>
}

extension TeslamateAPI: TopDrainLocationsAPIProviding {}

public struct SettingsBackedTopDrainLocationsAPI: TopDrainLocationsAPIProviding {
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
    public func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse> {
        await factory.request { await $0.topDrainLocations(carId: carId) }
    }
}

public struct TopDrainLocationsState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var hasLoadedData = false
    public var errorMessage: String?
    public var locations: [TopDrainLocation] = []
    public var units: TeslaMateServerStatsUnits?
    public init() {}
}

@MainActor
public final class TopDrainLocationsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<TopDrainLocationsState>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: TopDrainLocationsState
    private let api: any TopDrainLocationsAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<TopDrainLocationsState>
    private var carId: Int?

    public init(
        api: any TopDrainLocationsAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<TopDrainLocationsState>? = nil,
        initialState: TopDrainLocationsState = TopDrainLocationsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        switch await api.topDrainLocations(carId: carId) {
        case let .success(response):
            state.locations = response.locations
                .filter { GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil }
                .sorted { ($0.totalRangeLossKm ?? -.infinity) > ($1.totalRangeLossKm ?? -.infinity) }
            state.units = response.units
            state.hasLoadedData = true
            saveCachedState()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
    }

    public func refresh() async {
        guard let carId else { return }
        await load(carId: carId)
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }
}
