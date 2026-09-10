import XCTest
@testable import MateDriveApp

final class WeatherSelectionTests: XCTestCase {
    func testDriveEnvironmentSelectsValidPositionNearestTemporalMidpoint() throws {
        let first = SyntheticCoordinates.point()
        let middle = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let last = SyntheticCoordinates.point(latitudeOffset: 0.2, longitudeOffset: 0.2)
        let positions = [
            WeatherRoutePosition(latitude: first.latitude, longitude: first.longitude, date: "2026-07-18T08:00:00Z"),
            WeatherRoutePosition(latitude: middle.latitude, longitude: middle.longitude, date: "2026-07-18T08:52:00Z"),
            WeatherRoutePosition(latitude: last.latitude, longitude: last.longitude, date: "2026-07-18T10:00:00Z")
        ]

        let selected = try XCTUnwrap(WeatherSelection.driveEnvironmentPosition(positions: positions))

        XCTAssertEqual(selected.latitude, middle.latitude)
        XCTAssertEqual(selected.longitude, middle.longitude)
        XCTAssertEqual(selected.date, "2026-07-18T08:52:00Z")
    }

    func testDriveEnvironmentRejectsInvalidCoordinates() throws {
        let valid = SyntheticCoordinates.point()
        let positions = [
            WeatherRoutePosition(latitude: SyntheticCoordinates.invalidLatitude, longitude: valid.longitude, date: "2026-07-18T08:00:00Z"),
            WeatherRoutePosition(latitude: valid.latitude, longitude: valid.longitude, date: "2026-07-18T09:00:00Z")
        ]

        let selected = try XCTUnwrap(WeatherSelection.driveEnvironmentPosition(positions: positions))

        XCTAssertEqual(selected.latitude, valid.latitude)
    }

    func testDriveEnvironmentRequiresParseableHistoricalTimestamp() {
        let first = SyntheticCoordinates.point()
        let second = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let positions = [
            WeatherRoutePosition(latitude: first.latitude, longitude: first.longitude, date: nil),
            WeatherRoutePosition(latitude: second.latitude, longitude: second.longitude, date: "not-a-date")
        ]

        XCTAssertNil(WeatherSelection.driveEnvironmentPosition(positions: positions))
    }

    func testDriveWeatherSelectionUsesDocumentedDistanceThresholds() {
        let points = stride(from: 0, through: 100, by: 10).map {
            WeatherPositionWithDistance(position: WeatherRoutePosition(latitude: Double($0), longitude: 0, date: "2026-01-01T08:00:00Z"), cumulativeDistanceKm: Double($0))
        }

        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 9).map(\.cumulativeDistanceKm), [100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 20).map(\.cumulativeDistanceKm), [0, 100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 100).map(\.cumulativeDistanceKm), [0, 20, 50, 70, 100])
        XCTAssertEqual(WeatherSelection.selectWeatherPositions(positionsWithDistance: points, totalDistanceKm: 200).map(\.cumulativeDistanceKm), [0, 30, 70, 100])
    }

    func testCumulativeDistancesRejectInvalidCoordinatesWithoutPoisoningRoute() {
        let first = SyntheticCoordinates.point()
        let second = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let zero = SyntheticCoordinates.zero
        let positions = [
            WeatherRoutePosition(latitude: first.latitude, longitude: first.longitude, date: "2026-07-18T08:00:00Z"),
            WeatherRoutePosition(latitude: .nan, longitude: first.longitude, date: "2026-07-18T08:10:00Z"),
            WeatherRoutePosition(latitude: SyntheticCoordinates.invalidLatitude, longitude: first.longitude, date: "2026-07-18T08:20:00Z"),
            WeatherRoutePosition(latitude: zero.latitude, longitude: zero.longitude, date: "2026-07-18T08:30:00Z"),
            WeatherRoutePosition(latitude: second.latitude, longitude: second.longitude, date: "2026-07-18T08:40:00Z")
        ]

        let result = WeatherSelection.calculateCumulativeDistances(positions: positions)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].position.latitude, first.latitude)
        XCTAssertEqual(result[1].position.latitude, second.latitude)
        XCTAssertEqual(result[0].cumulativeDistanceKm, 0)
        XCTAssertTrue(result[1].cumulativeDistanceKm.isFinite)
        XCTAssertGreaterThan(result[1].cumulativeDistanceKm, 0)
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
