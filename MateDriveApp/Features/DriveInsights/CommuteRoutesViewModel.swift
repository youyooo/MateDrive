import Combine
import Foundation

public protocol CommuteRoutesAPIProviding: Sendable {
    func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse>
}

extension TeslamateAPI: CommuteRoutesAPIProviding {}

public struct SettingsBackedCommuteRoutesAPI: CommuteRoutesAPIProviding {
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

    public func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse> {
        await factory.request { await $0.commuteRoutes(carId: carId) }
    }
}

public struct CommuteRoutesState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var errorMessage: String?
    public var routes: [CommuteRoute] = []
    public var summary: CommuteRoutesSummary?
    public var units: TeslaMateServerStatsUnits?

    public init() {}
}

@MainActor
public final class CommuteRoutesViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<CommuteRoutesState>()

    @Published public private(set) var state: CommuteRoutesState
    private let api: any CommuteRoutesAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<CommuteRoutesState>

    public init(
        api: any CommuteRoutesAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<CommuteRoutesState>? = nil,
        initialState: CommuteRoutesState = CommuteRoutesState()
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
        state.isLoading = state.routes.isEmpty
        state.errorMessage = nil
        switch await api.commuteRoutes(carId: carId) {
        case let .success(response):
            state.routes = response.routes.sorted { ($0.tripCount ?? 0) > ($1.tripCount ?? 0) }
            state.summary = response.summary
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
