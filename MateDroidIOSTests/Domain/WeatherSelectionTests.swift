import XCTest
@testable import MateDroidIOS

final class WeatherSelectionTests: XCTestCase {
    func testDriveWeatherSelectionUsesAndroidDistanceThresholds() {
        let points = stride(from: 0, through: 100, by: 10).map {
            WeatherPositionWithDistance(position: WeatherRoutePosition(latitude: Double($0), longitude: 0, date: "2026-01-01T08:00:00Z"), cumulativeDistanceKm: Double($0))
        }

        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 9).map(\.cumulativeDistanceKm), [100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 20).map(\.cumulativeDistanceKm), [0, 100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 100).map(\.cumulativeDistanceKm), [0, 20, 50, 70, 100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 200).map(\.cumulativeDistanceKm), [0, 30, 70, 100])
    }

    func testTripWeatherSamplesAreHourlyClampedAndEvenlySpaced() {
        let drives = [
            TripDrive(id: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T12:00:00Z", distance: 100, durationMin: 240)
        ]
        let route = TripRouteSegment(points: (0..<9).map { TripRoutePoint(latitude: Double($0), longitude: 0) })

        let samples = WeatherSelection.selectTripSamples(drives: drives, routeSegments: [route])

        XCTAssertEqual(samples.map(\.latitude), [0, 2, 5, 8])
    }
}
