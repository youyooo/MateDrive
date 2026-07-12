import Foundation

public struct WeatherPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let weatherCode: Int

    public init(latitude: Double, longitude: Double, temperatureCelsius: Double, weatherCode: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.temperatureCelsius = temperatureCelsius
        self.weatherCode = weatherCode
    }
}

public protocol WeatherAPIProviding: Sendable {
    func weather(latitude: Double, longitude: Double, date: String?) async -> APIResult<WeatherPoint>
}

public actor WeatherService {
    private let api: any WeatherAPIProviding

    public init(api: any WeatherAPIProviding) {
        self.api = api
    }

    public func weatherAlongDrive(positions: [WeatherRoutePosition], totalDistanceKm: Double) async -> [WeatherPoint] {
        let selected = WeatherSelection.selectWeatherPositions(positions: positions, totalDistanceKm: totalDistanceKm)
        var points: [WeatherPoint] = []
        for selectedPosition in selected {
            guard let latitude = selectedPosition.position.latitude,
                  let longitude = selectedPosition.position.longitude
            else {
                continue
            }
            switch await api.weather(latitude: latitude, longitude: longitude, date: selectedPosition.position.date) {
            case let .success(point):
                points.append(point)
            case .failure:
                continue
            }
        }
        return points
    }

    public func weatherAlongTrip(drives: [TripDrive], routeSegments: [TripRouteSegment]) async -> [WeatherPoint] {
        let samples = WeatherSelection.selectTripSamples(drives: drives, routeSegments: routeSegments)
        var points: [WeatherPoint] = []
        for sample in samples {
            switch await api.weather(latitude: sample.latitude, longitude: sample.longitude, date: nil) {
            case let .success(point):
                points.append(point)
            case .failure:
                continue
            }
        }
        return points
    }
}
