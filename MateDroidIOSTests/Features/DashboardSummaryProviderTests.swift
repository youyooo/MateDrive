import Foundation
import XCTest
@testable import MateDroidIOS

final class DashboardSummaryProviderTests: XCTestCase {
    func testProviderSelectsNewestDriveAndCharge() async throws {
        let database = try await database()
        let drives = DriveSummaryStore(database: database)
        let charges = ChargeSummaryStore(database: database)
        try await drives.upsertAll([
            drive(id: 10, carId: 1, start: "2026-01-10T10:00:00Z", distance: 11),
            drive(id: 20, carId: 1, start: "2026-01-11T10:00:00Z", distance: 22)
        ])
        try await charges.upsertAll([
            charge(id: 20, carId: 1, start: "2026-01-10T08:00:00Z", end: "2026-01-10T09:00:00Z", odometer: 100),
            charge(id: 30, carId: 1, start: "2026-01-11T08:00:00Z", end: "2026-01-11T09:00:00Z", odometer: 200)
        ])

        let summary = try await provider(database: database).summary(carId: 1)

        XCTAssertEqual(summary.latestDrive?.driveId, 20)
        XCTAssertEqual(summary.latestDrive?.distanceKm, 22)
        XCTAssertEqual(summary.latestCharge?.chargeId, 30)
        XCTAssertEqual(summary.latestCharge?.odometerKm, 200)
        XCTAssertEqual(summary.odometerKm, 200)
    }

    func testProviderKeepsCarsIsolatedAndPreservesMissingOptionalValues() async throws {
        let database = try await database()
        let drives = DriveSummaryStore(database: database)
        let charges = ChargeSummaryStore(database: database)
        try await drives.upsertAll([
            drive(id: 10, carId: 1, start: "2026-01-10T10:00:00Z", distance: nil),
            drive(id: 20, carId: 2, start: "2026-01-11T10:00:00Z", distance: 22)
        ])
        try await charges.upsertAll([
            charge(id: 30, carId: 1, start: "2026-01-11T08:00:00Z", end: nil, odometer: nil),
            charge(id: 40, carId: 2, start: "2026-01-11T08:00:00Z", end: "2026-01-11T09:00:00Z", odometer: 200)
        ])

        let first = try await provider(database: database).summary(carId: 1)
        let missing = try await provider(database: database).summary(carId: 99)

        XCTAssertEqual(first.latestDrive?.driveId, 10)
        XCTAssertNil(first.latestDrive?.distanceKm)
        XCTAssertEqual(first.latestCharge?.chargeId, 30)
        XCTAssertNil(first.latestCharge?.endedAt)
        XCTAssertNil(first.odometerKm)
        XCTAssertNil(missing.latestDrive)
        XCTAssertNil(missing.latestCharge)
        XCTAssertNil(missing.odometerKm)
    }

    func testProviderCalculatesSleepSummariesFromLatestCompletedChargeAndCalendarPeriods() async throws {
        let database = try await database()
        let charges = ChargeSummaryStore(database: database)
        let sleeps = SleepIntervalStore(database: database)
        try await charges.upsertAll([
            charge(id: 10, carId: 1, start: "2026-01-13T05:00:00Z", end: nil, odometer: nil),
            charge(id: 20, carId: 1, start: "2026-01-12T05:00:00Z", end: "2026-01-12T06:00:00Z", odometer: nil)
        ])
        try await sleeps.upsertAll([
            SleepIntervalRecord(carId: 1, startDate: "2025-12-31T23:00:00Z", endDate: "2026-01-01T01:00:00Z"),
            SleepIntervalRecord(carId: 1, startDate: "2026-01-11T23:00:00Z", endDate: "2026-01-12T01:00:00Z"),
            SleepIntervalRecord(carId: 1, startDate: "2026-01-12T05:30:00Z", endDate: "2026-01-12T07:00:00Z"),
            SleepIntervalRecord(carId: 1, startDate: "2026-01-13T23:00:00Z", endDate: "2026-01-14T01:00:00Z")
        ])

        let summary = try await provider(database: database).summary(carId: 1)

        XCTAssertEqual(summary.sleepSummaries[.sinceCharge]?.duration, 10_800)
        XCTAssertEqual(summary.sleepSummaries[.today]?.duration, 3_600)
        XCTAssertEqual(summary.sleepSummaries[.week]?.duration, 16_200)
        XCTAssertEqual(summary.sleepSummaries[.month]?.duration, 23_400)
        XCTAssertTrue(summary.sleepSummaries.values.allSatisfy(\.isAvailable))
    }

    func testProviderIncludesSleepBeforeTheCurrentMonthForSinceCharge() async throws {
        let database = try await database()
        let charges = ChargeSummaryStore(database: database)
        let sleeps = SleepIntervalStore(database: database)
        try await charges.upsertAll([
            charge(id: 20, carId: 1, start: "2025-12-01T05:00:00Z", end: "2025-12-01T06:00:00Z", odometer: nil)
        ])
        try await sleeps.upsertAll([
            SleepIntervalRecord(carId: 1, startDate: "2025-12-15T00:00:00Z", endDate: "2025-12-15T01:00:00Z")
        ])

        let summary = try await provider(database: database).summary(carId: 1)

        XCTAssertEqual(summary.sleepSummaries[.sinceCharge]?.duration, 3_600)
    }

    private func provider(database: SQLiteDatabase) -> DashboardSummaryProvider {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDate = Date(timeIntervalSince1970: 1_768_392_000)
        return DashboardSummaryProvider(
            driveStore: DriveSummaryStore(database: database),
            chargeStore: ChargeSummaryStore(database: database),
            sleepIntervalStore: SleepIntervalStore(database: database),
            calendar: calendar,
            now: { currentDate }
        )
    }

    private func database() async throws -> SQLiteDatabase {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        return database
    }

    private func drive(id: Int, carId: Int, start: String, distance: Double?) -> DriveSummaryRecord {
        DriveSummaryRecord(
            driveId: id,
            carId: carId,
            startDate: start,
            endDate: start,
            distance: distance,
            durationMin: 15
        )
    }

    private func charge(id: Int, carId: Int, start: String, end: String?, odometer: Double?) -> ChargeSummaryRecord {
        ChargeSummaryRecord(
            chargeId: id,
            carId: carId,
            startDate: start,
            endDate: end,
            chargeEnergyAdded: 20,
            cost: 4,
            odometerKm: odometer
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
