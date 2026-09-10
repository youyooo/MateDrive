import Foundation
import XCTest
@testable import MateDriveApp

final class DashboardSummaryProviderTests: XCTestCase {
    func testOlderLatestDriveSnapshotDecodesWithoutIntelligencePayload() throws {
        let data = Data(#"{"driveId":42}"#.utf8)

        let drive = try JSONDecoder().decode(DashboardLatestDrive.self, from: data)

        XCTAssertEqual(drive.driveId, 42)
        XCTAssertNil(drive.intelligence)
    }

    func testProviderSelectsNewestDriveAndCharge() async throws {
        let database = try await database()
        let drives = DriveSummaryStore(database: database)
        let charges = ChargeSummaryStore(database: database)
        try await drives.upsertAll([
            drive(id: 10, carId: 1, start: "2026-01-10T10:00:00Z", distance: 11),
            drive(
                id: 20,
                carId: 1,
                start: "2026-01-11T10:00:00Z",
                distance: 22,
                startRatedRangeKm: 380,
                endRatedRangeKm: 342
            )
        ])
        try await charges.upsertAll([
            charge(id: 20, carId: 1, start: "2026-01-10T08:00:00Z", end: "2026-01-10T09:00:00Z", odometer: 100),
            charge(id: 30, carId: 1, start: "2026-01-11T08:00:00Z", end: "2026-01-11T09:00:00Z", odometer: 200)
        ])

        let summary = try await provider(database: database).summary(carId: 1)

        XCTAssertEqual(summary.latestDrive?.driveId, 20)
        XCTAssertEqual(summary.latestDrive?.distanceKm, 22)
        XCTAssertEqual(summary.latestDrive?.ratedRangeDropKm, 38)
        XCTAssertEqual(summary.latestDrive?.remainingRatedRangeKm, 342)
        XCTAssertEqual(summary.latestCharge?.chargeId, 30)
        XCTAssertEqual(summary.latestCharge?.odometerKm, 200)
        XCTAssertEqual(summary.odometerKm, 200)
        XCTAssertEqual(summary.completedDriveCount, 2)
        XCTAssertEqual(summary.completedChargeCount, 2)
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

    func testProviderRebuildsLatestDrivePersonalBestFromCachedRoutes() async throws {
        let database = try await database()
        let drives = DriveSummaryStore(database: database)
        let fingerprint = DriveRouteFingerprint(points: (0..<4).map { index in
            let point = SyntheticCoordinates.point(
                latitudeOffset: Double(index) * 0.01,
                longitudeOffset: Double(index) * 0.01
            )
            return DriveRoutePoint(latitude: point.latitude, longitude: point.longitude)
        })
        let routeJSON = String(data: try JSONEncoder().encode(fingerprint), encoding: .utf8)!
        try await drives.upsertAll([
            drive(id: 1, carId: 1, start: "2026-01-05T08:00:00Z", distance: 20, consumptionNet: 210, routeJSON: routeJSON),
            drive(id: 2, carId: 1, start: "2026-01-06T08:00:00Z", distance: 20, consumptionNet: 200, routeJSON: routeJSON),
            drive(id: 3, carId: 1, start: "2026-01-07T08:00:00Z", distance: 20, consumptionNet: 190, routeJSON: routeJSON),
            drive(id: 4, carId: 1, start: "2026-01-08T08:00:00Z", distance: 20, consumptionNet: 180, routeJSON: routeJSON),
            drive(id: 5, carId: 1, start: "2026-01-09T08:00:00Z", distance: 20, consumptionNet: 150, routeJSON: routeJSON)
        ])
        let settings = AppSettings(
            driveRouteLabelRules: [
                DriveRouteLabelRule(
                    carId: 1,
                    name: "上班通勤",
                    typicalDistanceKm: 20,
                    fingerprint: fingerprint
                )
            ]
        )
        let settingsStore = StaticDashboardSettingsStore(settings: settings)

        let summary = try await provider(database: database, settingsStore: settingsStore).summary(carId: 1)

        XCTAssertEqual(summary.latestDrive?.driveId, 5)
        XCTAssertEqual(summary.latestDrive?.intelligence?.benchmark.benchmarkEfficiency, 195)
        XCTAssertEqual(summary.latestDrive?.intelligence?.benchmark.previousBestEfficiency, 180)
        XCTAssertEqual(summary.latestDrive?.intelligence?.benchmark.accent, .personalBest)
    }

    private func provider(
        database: SQLiteDatabase,
        settingsStore: (any SettingsStoring)? = nil
    ) -> DashboardSummaryProvider {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDate = Date(timeIntervalSince1970: 1_768_392_000)
        return DashboardSummaryProvider(
            driveStore: DriveSummaryStore(database: database),
            chargeStore: ChargeSummaryStore(database: database),
            sleepIntervalStore: SleepIntervalStore(database: database),
            settingsStore: settingsStore,
            calendar: calendar,
            now: { currentDate }
        )
    }

    private func database() async throws -> SQLiteDatabase {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        return database
    }

    private func drive(
        id: Int,
        carId: Int,
        start: String,
        distance: Double?,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        consumptionNet: Double? = nil,
        routeJSON: String? = nil
    ) -> DriveSummaryRecord {
        DriveSummaryRecord(
            driveId: id,
            carId: carId,
            startDate: start,
            endDate: start,
            distance: distance,
            durationMin: 15,
            consumptionNet: consumptionNet,
            startRatedRangeKm: startRatedRangeKm,
            endRatedRangeKm: endRatedRangeKm,
            routeFingerprintJSON: routeJSON
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

private actor StaticDashboardSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        self.settings = settings
    }
}
