import Combine
import Foundation

public struct DriveReplaySample: Equatable, Sendable {
    public let position: DrivePosition
    public let latitude: Double
    public let longitude: Double

    public init(position: DrivePosition, latitude: Double, longitude: Double) {
        self.position = position
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum DriveReplayBuilder {
    public static func samples(from positions: [DrivePosition]) -> [DriveReplaySample] {
        var accepted: [DriveReplaySample] = []
        for position in positions {
            guard let location = GeoCoordinateValidator.location(latitude: position.latitude, longitude: position.longitude) else {
                continue
            }
            if let previous = accepted.last {
                let route = GeoCoordinateValidator.sanitizedRoute([
                    GeocodeRouteSample(latitude: previous.latitude, longitude: previous.longitude, date: previous.position.date),
                    GeocodeRouteSample(latitude: location.latitude, longitude: location.longitude, date: position.date)
                ])
                guard route.count == 2 else { continue }
            }
            accepted.append(DriveReplaySample(position: position, latitude: location.latitude, longitude: location.longitude))
        }
        return accepted
    }
}

public struct DriveWeatherPoint: Equatable, Identifiable, Sendable {
    public var id: String { "\(latitude),\(longitude),\(temperatureCelsius),\(weatherCode)" }

    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let weatherCode: Int

    public init(point: WeatherPoint) {
        self.latitude = point.latitude
        self.longitude = point.longitude
        self.temperatureCelsius = point.temperatureCelsius
        self.weatherCode = point.weatherCode
    }
}

public struct DriveDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var isLoadingWeather: Bool
    public var errorMessage: String?
    public var driveDetail: DriveDetail?
    public var units: UnitPreferences?
    public var stats: DriveDetailStats?
    public var weatherPoints: [DriveWeatherPoint]
    public var tripMembership: TripMembership?
    public var annotation: DriveAnnotation

    public init(
        isLoading: Bool = true,
        isLoadingWeather: Bool = false,
        errorMessage: String? = nil,
        driveDetail: DriveDetail? = nil,
        units: UnitPreferences? = nil,
        stats: DriveDetailStats? = nil,
        weatherPoints: [DriveWeatherPoint] = [],
        tripMembership: TripMembership? = nil,
        annotation: DriveAnnotation = DriveAnnotation()
    ) {
        self.isLoading = isLoading
        self.isLoadingWeather = isLoadingWeather
        self.errorMessage = errorMessage
        self.driveDetail = driveDetail
        self.units = units
        self.stats = stats
        self.weatherPoints = weatherPoints
        self.tripMembership = tripMembership
        self.annotation = annotation
    }
}

@MainActor
public final class DriveDetailViewModel: ObservableObject {
    @Published public private(set) var state: DriveDetailState

    private let api: any DriveAPIProviding
    private let weatherService: (any DriveWeatherServicing)?
    private let tripMembershipManager: (any TripMembershipManaging)?
    private let settingsStore: (any SettingsStoring)?

    public init(
        api: any DriveAPIProviding,
        weatherService: (any DriveWeatherServicing)? = nil,
        tripMembershipManager: (any TripMembershipManaging)? = nil,
        settingsStore: (any SettingsStoring)? = nil,
        initialState: DriveDetailState = DriveDetailState()
    ) {
        self.api = api
        self.weatherService = weatherService
        self.tripMembershipManager = tripMembershipManager
        self.settingsStore = settingsStore
        self.state = initialState
    }

    public func load(carId: Int, driveId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        state.weatherPoints = []

        async let detailResult = api.driveDetail(carId: carId, driveId: driveId)
        async let statusResult = api.carStatus(carId: carId)
        async let membershipResult = loadMembership(carId: carId, driveId: driveId)
        async let annotationResult = loadAnnotation(carId: carId, driveId: driveId)

        switch await statusResult {
        case let .success(payload):
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        case .failure:
            state.units = nil
        }

        switch await detailResult {
        case let .success(detail):
            state.driveDetail = detail
            state.stats = DriveStatsCalculator.calculateStats(detail)
            state.isLoading = false
            await loadWeather(detail)
        case let .failure(error):
            state.isLoading = false
            state.isLoadingWeather = false
            state.errorMessage = error.driveMessage
        }
        state.tripMembership = await membershipResult
        state.annotation = await annotationResult
    }

    public func saveAnnotation(carId: Int, driveId: Int, annotation: DriveAnnotation) async {
        guard let settingsStore else { state.annotation = annotation; return }
        var settings = await settingsStore.load()
        settings.setDriveAnnotation(annotation, carId: carId, driveId: driveId)
        await settingsStore.save(settings)
        state.annotation = annotation
    }

    public func removeFromTrip(carId: Int, driveId: Int) async {
        guard let tripMembershipManager else { return }
        do {
            try await tripMembershipManager.remove(carId: carId, leg: .drive(driveId))
            state.tripMembership = nil
            state.errorMessage = nil
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func loadMembership(carId: Int, driveId: Int) async -> TripMembership? {
        try? await tripMembershipManager?.membership(carId: carId, leg: .drive(driveId))
    }

    private func loadAnnotation(carId: Int, driveId: Int) async -> DriveAnnotation {
        guard let settingsStore else { return DriveAnnotation() }
        return (await settingsStore.load()).driveAnnotation(carId: carId, driveId: driveId)
    }

    private func loadWeather(_ detail: DriveDetail) async {
        guard let weatherService,
              let positions = detail.positions,
              let distance = detail.distance,
              !positions.isEmpty,
              distance > 0
        else {
            return
        }

        state.isLoadingWeather = true
        let routePositions = positions.map {
            WeatherRoutePosition(latitude: $0.latitude, longitude: $0.longitude, date: $0.date)
        }
        let points = await weatherService.weatherAlongDrive(positions: routePositions, totalDistanceKm: distance)
        state.weatherPoints = points.map(DriveWeatherPoint.init(point:))
        state.isLoadingWeather = false
    }
}
