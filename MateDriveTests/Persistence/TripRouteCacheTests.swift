import XCTest
@testable import MateDriveApp

final class TripRouteCacheTests: XCTestCase {
    func testRouteCacheRoundTripIsIsolatedByVehicleAndDrive() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let cache = DatabaseBackedTripRouteCache(databaseProvider: TripRouteStaticDatabaseProvider(database: database))
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let points = [
            GeocodeLocation(latitude: firstPoint.latitude, longitude: firstPoint.longitude),
            GeocodeLocation(latitude: secondPoint.latitude, longitude: secondPoint.longitude)
        ]

        try await cache.save(points: points, carId: 1, driveId: 10)

        let restored = try await cache.points(carId: 1, driveId: 10)
        XCTAssertEqual(restored, points)
        let otherCar = try await cache.points(carId: 2, driveId: 10)
        XCTAssertNil(otherCar)
        let otherDrive = try await cache.points(carId: 1, driveId: 11)
        XCTAssertNil(otherDrive)
    }
}

private struct TripRouteStaticDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase { database }
}
