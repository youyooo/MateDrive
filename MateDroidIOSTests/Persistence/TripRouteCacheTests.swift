import XCTest
@testable import MateDroidIOS

final class TripRouteCacheTests: XCTestCase {
    func testRouteCacheRoundTripIsIsolatedByVehicleAndDrive() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let cache = DatabaseBackedTripRouteCache(databaseProvider: TripRouteStaticDatabaseProvider(database: database))
        let points = [
            GeocodeLocation(latitude: 28.20, longitude: 112.85),
            GeocodeLocation(latitude: 28.21, longitude: 112.86)
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
