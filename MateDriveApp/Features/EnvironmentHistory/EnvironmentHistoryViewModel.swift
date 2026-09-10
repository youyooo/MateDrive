import Combine
import Foundation

public enum EnvironmentHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case oneYear = "1y"
    public var id: String { rawValue }
    public var grain: String { self == .sevenDays ? "hour" : "day" }
}

public struct EnvironmentHistoryState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var errorMessage: String?
    public var response: EnvironmentHistoryResponse?
    public var range: EnvironmentHistoryRange = .thirtyDays
    public init() {}
}

@MainActor
public final class EnvironmentHistoryViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<EnvironmentHistoryState>()

    @Published public private(set) var state: EnvironmentHistoryState
    private let api: any EnvironmentHistoryAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<EnvironmentHistoryState>

    public init(
        api: any EnvironmentHistoryAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<EnvironmentHistoryState>? = nil,
        initialState: EnvironmentHistoryState = EnvironmentHistoryState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public var datedPoints: [EnvironmentHistoryPoint] {
        (state.response?.data.series ?? [])
            .compactMap { point -> (point: EnvironmentHistoryPoint, timestamp: Date)? in
                guard let timestamp = point.timestamp else { return nil }
                return (point, timestamp)
            }
            .sorted { $0.timestamp < $1.timestamp }
            .map(\.point)
    }

    public func select(_ range: EnvironmentHistoryRange, carId: Int) async {
        guard state.range != range else { return }
        let previousRange = state.range
        state.range = range
        await load(carId: carId)
        if state.errorMessage != nil, state.response != nil {
            state.range = previousRange
        }
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.response == nil
        state.errorMessage = nil
        let result = await api.environmentHistory(carId: carId, range: state.range.rawValue, grain: state.range.grain)
        switch result {
        case let .success(response):
            state.response = response
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
