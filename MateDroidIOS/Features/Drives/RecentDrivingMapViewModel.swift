import Combine
import Foundation

public protocol DrivingCoordinatesAPIProviding: Sendable {
    func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse>
}

extension TeslamateAPI: DrivingCoordinatesAPIProviding {}

public struct SettingsBackedDrivingCoordinatesAPI: DrivingCoordinatesAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory
    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
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
    @Published public private(set) var state: RecentDrivingMapState
    private let api: any DrivingCoordinatesAPIProviding

    public init(api: any DrivingCoordinatesAPIProviding, initialState: RecentDrivingMapState = RecentDrivingMapState()) {
        self.api = api
        state = initialState
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        switch await api.drivingCoordinates(carId: carId) {
        case let .success(response):
            let valid = response.data.coordinates.filter {
                $0.driveId != nil && GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil
            }
            state.invalidPointCount = response.data.coordinates.count - valid.count
            state.routes = Dictionary(grouping: valid, by: { $0.driveId! })
                .map { driveId, points in
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
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }

    private func date(_ value: String?) -> Date? { value.flatMap { DomainDateParser.date(from: $0) } }
}
