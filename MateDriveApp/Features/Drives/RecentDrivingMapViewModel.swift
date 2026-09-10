import Combine
import Foundation

public protocol DrivingCoordinatesAPIProviding: Sendable {
    func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse>
}

extension TeslamateAPI: DrivingCoordinatesAPIProviding {}

public struct SettingsBackedDrivingCoordinatesAPI: DrivingCoordinatesAPIProviding {
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
    public func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse> {
        await factory.request { await $0.drivingCoordinates(carId: carId) }
    }
}

public struct RecentDrivingRoute: Equatable, Identifiable, Sendable {
    public let id: Int
    public let points: [DrivingCoordinate]
    public let startedAt: Date?
    public let endedAt: Date?
    public let maximumSpeed: Double?
}

public struct RecentDrivingMapState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var errorMessage: String?
    public var routes: [RecentDrivingRoute] = []
    public var originalPointCount: Int?
    public var simplifiedPointCount: Int?
    public var invalidPointCount = 0
    public var units: DrivingCoordinateUnits?
    public init() {}
}

@MainActor
public final class RecentDrivingMapViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<RecentDrivingMapState>()

    @Published public private(set) var state: RecentDrivingMapState
    private let api: any DrivingCoordinatesAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<RecentDrivingMapState>

    public init(
        api: any DrivingCoordinatesAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<RecentDrivingMapState>? = nil,
        initialState: RecentDrivingMapState = RecentDrivingMapState()
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
        switch await api.drivingCoordinates(carId: carId) {
        case let .success(response):
            let valid = response.data.coordinates.compactMap {
                point -> (driveId: Int, point: DrivingCoordinate)? in
                guard let driveId = point.driveId,
                      GeoCoordinateValidator.location(
                          latitude: point.latitude,
                          longitude: point.longitude
                      ) != nil
                else {
                    return nil
                }
                return (driveId, point)
            }
            state.invalidPointCount = response.data.coordinates.count - valid.count
            state.routes = Dictionary(grouping: valid, by: \.driveId)
                .map { driveId, values in
                    let points = values.map(\.point)
                    let sorted = points.sorted { (date($0.date) ?? .distantPast) < (date($1.date) ?? .distantPast) }
                    return RecentDrivingRoute(
                        id: driveId,
                        points: sorted,
                        startedAt: sorted.compactMap { date($0.date) }.min(),
                        endedAt: sorted.compactMap { date($0.date) }.max(),
                        maximumSpeed: sorted.compactMap(\.speed).max()
                    )
                }
                .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
            state.originalPointCount = response.data.originalPoints
            state.simplifiedPointCount = response.data.simplifiedPoints
            state.units = response.data.units
            saveCachedState()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
        state.isRefreshing = false
    }

    private func date(_ value: String?) -> Date? { value.flatMap { DomainDateParser.date(from: $0) } }

    private func saveCachedState() {
        guard let cacheKey else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }
}
