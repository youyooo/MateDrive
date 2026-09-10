import Combine
import Foundation

public struct StandbyDrainState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var hasLoadedData = false
    public var errorMessage: String?
    public var data: StandbyDrainData?
    public var units: StandbyDrainUnits?

    public init() {}
}

@MainActor
public final class StandbyDrainViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<StandbyDrainState>(
        maximumEntryCount: 12
    )

    @Published public private(set) var state: StandbyDrainState

    private let api: any ActivityAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<StandbyDrainState>

    public init(
        api: any ActivityAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<StandbyDrainState>? = nil
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
            ?? StandbyDrainState()
    }

    public func load(carId: Int, latitude: Double, longitude: Double) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        switch await api.standbyDrain(carId: carId, latitude: latitude, longitude: longitude) {
        case let .success(response):
            state.data = response.data
            state.units = response.units
            state.hasLoadedData = true
            if response.data == nil {
                state.errorMessage = response.error
            }
            saveCachedState(preservingError: response.data == nil)
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
    }

    public static func cacheScope(latitude: Double, longitude: Double) -> String {
        let latitudeE5 = Int((latitude * 100_000).rounded())
        let longitudeE5 = Int((longitude * 100_000).rounded())
        return "standby:\(latitudeE5):\(longitudeE5)"
    }

    private func saveCachedState(preservingError: Bool) {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        if !preservingError {
            snapshot.errorMessage = nil
        }
        stateCache.save(snapshot, for: cacheKey)
    }
}
