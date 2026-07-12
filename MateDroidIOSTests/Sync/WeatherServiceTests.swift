import XCTest
@testable import MateDroidIOS

final class WeatherServiceTests: XCTestCase {
    func testDriveWeatherUsesRouteSelectionBeforeCallingApi() async {
        let api = FakeWeatherAPI()
        let service = WeatherService(api: api)
        let positions = [
            WeatherRoutePosition(latitude: 48.0, longitude: 2.0, date: "2026-01-01"),
            WeatherRoutePosition(latitude: 48.1, longitude: 2.1, date: "2026-01-01"),
            WeatherRoutePosition(latitude: 48.2, longitude: 2.2, date: "2026-01-01")
        ]

        let points = await service.weatherAlongDrive(positions: positions, totalDistanceKm: 20)

        XCTAssertEqual(points.map(\.latitude), [48.0, 48.2])
        let requestedLatitudes = await api.requestedLatitudeSnapshot()
        XCTAssertEqual(requestedLatitudes, [48.0, 48.2])
    }

    func testTripWeatherUsesHourlyClampedSamples() async {
        let api = FakeWeatherAPI()
        let service = WeatherService(api: api)
        let drives = [
            TripDrive(id: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T12:00:00Z", distance: 100, durationMin: 240)
        ]
        let route = TripRouteSegment(points: (0..<9).map { TripRoutePoint(latitude: Double($0), longitude: 0) })

        _ = await service.weatherAlongTrip(drives: drives, routeSegments: [route])

        let requestedLatitudes = await api.requestedLatitudeSnapshot()
        XCTAssertEqual(requestedLatitudes, [0, 2, 5, 8])
    }
}

private actor FakeWeatherAPI: WeatherAPIProviding {
    private(set) var requestedLatitudes: [Double] = []

    func weather(latitude: Double, longitude: Double, date _: String?) async -> APIResult<WeatherPoint> {
        requestedLatitudes.append(latitude)
        return .success(WeatherPoint(latitude: latitude, longitude: longitude, temperatureCelsius: 20, weatherCode: 0))
    }

    func requestedLatitudeSnapshot() -> [Double] {
        requestedLatitudes
    }
}
