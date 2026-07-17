import XCTest
@testable import MateDroidIOS

final class SleepIntervalStoreTests: XCTestCase {
    func testUpsertingDuplicateIntervalKeepsOneRow() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = SleepIntervalStore(database: database)
        let interval = SleepIntervalRecord(
            carId: 7,
            startDate: "2026-07-01T00:00:00Z",
            endDate: "2026-07-01T02:00:00Z"
        )

        try await store.upsertAll([interval, interval])

        let records = try await store.records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-01T03:00:00Z"
        )
        XCTAssertEqual(records, [interval])
    }

    func testRecordsKeepCarsIsolated() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = SleepIntervalStore(database: database)
        let firstCar = SleepIntervalRecord(
            carId: 7,
            startDate: "2026-07-01T00:00:00Z",
            endDate: "2026-07-01T02:00:00Z"
        )
        let secondCar = SleepIntervalRecord(
            carId: 8,
            startDate: "2026-07-01T00:00:00Z",
            endDate: "2026-07-01T02:00:00Z"
        )

        try await store.upsertAll([firstCar, secondCar])

        let records = try await store.records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-01T03:00:00Z"
        )
        XCTAssertEqual(records, [firstCar])
    }

    func testRecordsReturnsIntervalsOverlappingRequestedRangeInStartOrder() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = SleepIntervalStore(database: database)
        let first = SleepIntervalRecord(
            carId: 7,
            startDate: "2026-07-01T00:30:00Z",
            endDate: "2026-07-01T01:30:00Z"
        )
        let second = SleepIntervalRecord(
            carId: 7,
            startDate: "2026-07-01T01:30:00Z",
            endDate: "2026-07-01T02:30:00Z"
        )
        let excluded = SleepIntervalRecord(
            carId: 7,
            startDate: "2026-07-01T02:30:00Z",
            endDate: "2026-07-01T03:00:00Z"
        )

        try await store.upsertAll([second, excluded, first])

        let records = try await store.records(
            carId: 7,
            start: "2026-07-01T01:00:00Z",
            end: "2026-07-01T02:00:00Z"
        )
        XCTAssertEqual(records, [first, second])
    }
}
