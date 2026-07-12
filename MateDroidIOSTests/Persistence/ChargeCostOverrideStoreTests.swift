import XCTest
@testable import MateDroidIOS

final class ChargeCostOverrideStoreTests: XCTestCase {
    func testDatabaseBackedStoreRejectsNegativeCostOverride() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let provider = StaticDatabaseProvider(database: database)
        let store = DatabaseBackedChargeCostOverrideStore(databaseProvider: provider)

        try await store.saveCostOverride(carId: 1, chargeId: 12, cost: 8.25)

        do {
            try await store.saveCostOverride(carId: 1, chargeId: 12, cost: -1)
            XCTFail("Expected negative charge cost override to be rejected.")
        } catch ChargeCostOverrideValidationError.invalidCost {
            let saved = try await store.costOverride(carId: 1, chargeId: 12)
            XCTAssertEqual(saved, 8.25)
        }
    }

    func testDatabaseBackedStoreRejectsNonFiniteCostOverride() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let provider = StaticDatabaseProvider(database: database)
        let store = DatabaseBackedChargeCostOverrideStore(databaseProvider: provider)

        do {
            try await store.saveCostOverride(carId: 1, chargeId: 12, cost: .infinity)
            XCTFail("Expected non-finite charge cost override to be rejected.")
        } catch ChargeCostOverrideValidationError.invalidCost {
            let saved = try await store.costOverride(carId: 1, chargeId: 12)
            XCTAssertNil(saved)
        }
    }
}

private struct StaticDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase {
        database
    }
}
