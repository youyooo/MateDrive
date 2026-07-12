import XCTest
@testable import MateDroidIOS

final class WeatherServiceTests: XCTestCase {
    func testDriveWeatherUsesRouteSelectionBeforeCallingApi() async {
        let api = FakeWeatherAPI()
        let service = WeatherService(api: api)
        let firstPoint = SyntheticCoordinates.point()
        let middlePoint = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let finalPoint = SyntheticCoordinates.point(latitudeOffset: 0.2, longitudeOffset: 0.2)
        let positions = [
            WeatherRoutePosition(latitude: firstPoint.latitude, longitude: firstPoint.longitude, date: "2026-01-01"),
            WeatherRoutePosition(latitude: middlePoint.latitude, longitude: middlePoint.longitude, date: "2026-01-01"),
            WeatherRoutePosition(latitude: finalPoint.latitude, longitude: finalPoint.longitude, date: "2026-01-01")
        ]

        let points = await service.weatherAlongDrive(positions: positions, totalDistanceKm: 20)

        XCTAssertEqual(points.map(\.latitude), [firstPoint.latitude, finalPoint.latitude])
        let requestedLatitudes = await api.requestedLatitudeSnapshot()
        XCTAssertEqual(requestedLatitudes, [firstPoint.latitude, finalPoint.latitude])
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
