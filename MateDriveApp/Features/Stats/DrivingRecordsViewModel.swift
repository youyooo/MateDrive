import Combine
import Foundation

public protocol DrivingRecordsAPIProviding: Sendable {
    func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse>
}

extension TeslamateAPI: DrivingRecordsAPIProviding {}

public struct SettingsBackedDrivingRecordsAPI: DrivingRecordsAPIProviding {
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
    public func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse> {
        await factory.request { await $0.statsExtremes(carId: carId) }
    }
}

public struct DrivingRecordsState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var errorMessage: String?
    public var records: [StatsExtreme] = []
    public var units: TeslaMateServerStatsUnits?
    public init() {}
}

@MainActor
public final class DrivingRecordsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<DrivingRecordsState>()

    @Published public private(set) var state: DrivingRecordsState
    private let api: any DrivingRecordsAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<DrivingRecordsState>

    public init(
        api: any DrivingRecordsAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<DrivingRecordsState>? = nil,
        initialState: DrivingRecordsState = DrivingRecordsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.records.isEmpty
        state.errorMessage = nil
        switch await api.statsExtremes(carId: carId) {
        case let .success(response):
            state.records = response.extremes
            state.units = response.units
            saveCachedState()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
        state.isRefreshing = false
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }
}
