import XCTest
@testable import MateDroidIOS

final class PersistenceMigrationTests: XCTestCase {
    func testMigratingEmptyDatabaseCreatesRequiredTablesAtCurrentVersionWithoutInvalidatingDetailAggregates() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)

        let tables = try await database.tableNames()
        XCTAssertTrue(tables.contains("sync_state"))
        XCTAssertTrue(tables.contains("drives_summary"))
        XCTAssertTrue(tables.contains("charges_summary"))
        XCTAssertTrue(tables.contains("drive_detail_aggregates"))
        XCTAssertTrue(tables.contains("charge_detail_aggregates"))
        XCTAssertTrue(tables.contains("charge_cost_overrides"))
        XCTAssertTrue(tables.contains("teslamate_capabilities"))
        XCTAssertTrue(tables.contains("geocode_cache"))
        XCTAssertTrue(tables.contains("geocode_queue"))
        XCTAssertTrue(tables.contains("geocode_progress"))
        XCTAssertTrue(tables.contains("sentry_alert_log"))
        XCTAssertTrue(tables.contains("trip_route_cache"))
        XCTAssertTrue(tables.contains("trip_country_cache"))
        XCTAssertTrue(tables.contains("saved_trips"))
        XCTAssertTrue(tables.contains("saved_trip_legs"))
        XCTAssertTrue(tables.contains("saved_trip_consumed_fingerprints"))
        XCTAssertTrue(tables.contains("charge_pricing_audit_batches"))
        XCTAssertTrue(tables.contains("charge_pricing_audit_items"))
        XCTAssertTrue(tables.contains("sleep_intervals"))
        let version = try await database.userVersion()
        XCTAssertEqual(version, 20)
        XCTAssertEqual(DatabaseSchemaVersion.current, 20)
        XCTAssertEqual(SchemaVersion.current, 13)
    }

    func testVersion20CreatesSleepIntervalsWithCompositePrimaryKeyAndRangeIndex() async throws {
        let database = try SQLiteDatabase.inMemory()

        try await Migrations.applyAll(to: database)

        let columns = try await database.rows("PRAGMA table_info(sleep_intervals);")
        let primaryKeyColumns = columns.compactMap { row -> String? in
            guard row.count >= 6, let name = row[1].textValue, let position = row[5].intValue else {
                return nil
            }
            return position > 0 ? name : nil
        }
        let indexes = try await database.rows("PRAGMA index_list(sleep_intervals);")
        let version = try await database.userVersion()

        XCTAssertEqual(columns.map { $0[1].textValue }, ["car_id", "start_date", "end_date"])
        XCTAssertEqual(primaryKeyColumns, ["car_id", "start_date", "end_date"])
        XCTAssertTrue(indexes.contains { $0.count >= 2 && $0[1].textValue == "sleep_intervals_car_range" })
        XCTAssertEqual(version, 20)
    }

    func testDriveSummarySchemaPreservesMissingDistanceAndDuration() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DriveSummaryStore(database: database)

        try await store.upsertAll([
            DriveSummaryRecord(driveId: 1, carId: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T08:30:00Z", distance: nil, durationMin: nil)
        ])
        try await Migrations.applyAll(to: database)

        let rows = try await database.rows("SELECT distance, duration_min FROM drives_summary WHERE drive_id = 1;")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row, [.null, .null])
    }

    func testVersion14DriveSummariesMigrateWithoutDataLoss() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL NOT NULL,
              duration_min INTEGER NOT NULL,
              schema_version INTEGER NOT NULL DEFAULT 12
            );
            """)
        try await database.execute("INSERT INTO drives_summary VALUES (7, 1, 'start', 'end', 12.5, 30, 13);")
        try await database.setUserVersion(14)

        try await Migrations.applyAll(to: database)

        let migrated = try await database.rows("SELECT drive_id, distance, duration_min FROM drives_summary;")
        XCTAssertEqual(migrated, [[.int(7), .double(12.5), .int(30)]])
        let store = DriveSummaryStore(database: database)
        try await store.upsertAll([
            DriveSummaryRecord(driveId: 8, carId: 1, startDate: "start", endDate: "end", distance: nil, durationMin: nil)
        ])
        let missing = try await database.rows("SELECT distance, duration_min FROM drives_summary WHERE drive_id = 8;")
        XCTAssertEqual(missing, [[.null, .null]])
        let version = try await database.userVersion()
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
    }

    func testVersion15DriveSummariesGainNullableEnergyFieldsWithoutDataLoss() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13
            );
            """)
        try await database.execute("INSERT INTO drives_summary VALUES (7, 1, 'start', 'end', 12.5, 30, 13);")
        try await database.setUserVersion(15)

        try await Migrations.applyAll(to: database)

        let migrated = try await database.rows("SELECT drive_id, distance, duration_min, energy_consumed_net, consumption_net FROM drives_summary;")
        XCTAssertEqual(migrated, [[.int(7), .double(12.5), .int(30), .null, .null]])
        let version = try await database.userVersion()
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
    }
}
