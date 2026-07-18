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
        XCTAssertTrue(tables.contains("vehicle_activity_sessions"))
        XCTAssertTrue(tables.contains("activity_label_overrides"))
        XCTAssertTrue(tables.contains("charge_pricing_observations"))
        let version = try await database.userVersion()
        XCTAssertEqual(version, 23)
        XCTAssertEqual(DatabaseSchemaVersion.current, 23)
        XCTAssertEqual(SchemaVersion.current, 13)
    }

    func testMigration23CreatesSmartActivityTablesAndIndexes() async throws {
        let database = try SQLiteDatabase.inMemory()

        try await Migrations.applyAll(to: database)

        let version = try await database.userVersion()
        XCTAssertEqual(version, 23)
        for table in [
            "vehicle_activity_sessions",
            "activity_label_overrides",
            "charge_pricing_observations"
        ] {
            let rows = try await database.rows(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
                bindings: [.text(table)]
            )
            XCTAssertEqual(rows.count, 1)
        }
        let sessionIndexes = try await database.rows("PRAGMA index_list(vehicle_activity_sessions);")
        let observationIndexes = try await database.rows("PRAGMA index_list(charge_pricing_observations);")
        XCTAssertTrue(sessionIndexes.contains { $0.count >= 2 && $0[1].textValue == "vehicle_activity_sessions_car_date" })
        XCTAssertTrue(observationIndexes.contains { $0.count >= 2 && $0[1].textValue == "charge_pricing_observations_station" })
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
        XCTAssertEqual(version, 23)
    }

    func testVersion20AddsDriveRatedRangeColumnsWithoutLosingExistingRows() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await createVersion18ChargeSummaryTable(in: database)
        try await createVersion19DriveSummaryTable(in: database)
        try await database.execute("INSERT INTO drives_summary VALUES (10, 1, 'start', 'end', 20, 30, 14, 4.2, 210, 'api', 80, 70);")
        try await database.execute("CREATE TABLE sleep_intervals (car_id INTEGER NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, PRIMARY KEY(car_id, start_date, end_date));")
        try await database.setUserVersion(20)

        try await Migrations.applyAll(to: database)

        let rows = try await database.rows(
            "SELECT drive_id, distance, start_rated_range_km, end_rated_range_km FROM drives_summary;"
        )
        let version = try await database.userVersion()
        XCTAssertEqual(rows, [[.int(10), .double(20), .null, .null]])
        XCTAssertEqual(version, 23)
    }

    func testVersion20RawSQLUpgradeAppliesMigrations21Through23WithoutDataLoss() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13,
              energy_consumed_net REAL,
              consumption_net REAL,
              energy_source TEXT,
              start_battery_level INTEGER,
              end_battery_level INTEGER
            );
            """)
        try await database.execute("""
            INSERT INTO drives_summary
            (drive_id, car_id, start_date, end_date, distance, duration_min, schema_version,
             energy_consumed_net, consumption_net, energy_source, start_battery_level, end_battery_level)
            VALUES (10, 1, 'start', 'end', 20, 30, 13, 4.2, 210, 'api', 80, 70);
            """)
        try await database.setUserVersion(20)

        try await Migrations.applyAll(to: database)

        let requiredColumns: Set<String> = [
            "start_rated_range_km", "end_rated_range_km", "start_address", "end_address",
            "speed_avg", "outside_temp_avg", "route_fingerprint_json", "climate_on_fraction",
            "elevation_gain_m", "elevation_loss_m"
        ]
        let columns = Set(
            try await database.rows("PRAGMA table_info(drives_summary);")
                .compactMap { $0[1].textValue }
        )
        XCTAssertTrue(requiredColumns.isSubset(of: columns))
        for table in [
            "vehicle_activity_sessions",
            "activity_label_overrides",
            "charge_pricing_observations"
        ] {
            let rows = try await database.rows(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
                bindings: [.text(table)]
            )
            XCTAssertEqual(rows, [[.text(table)]])
        }
        let rows = try await database.rows(
            """
            SELECT drive_id, car_id, start_date, end_date, distance, duration_min,
                   energy_consumed_net, consumption_net, energy_source,
                   start_battery_level, end_battery_level,
                   start_rated_range_km, end_rated_range_km,
                   start_address, end_address, speed_avg, outside_temp_avg,
                   route_fingerprint_json, climate_on_fraction, elevation_gain_m, elevation_loss_m
            FROM drives_summary;
            """
        )
        XCTAssertEqual(rows, [[
            .int(10), .int(1), .text("start"), .text("end"), .double(20), .int(30),
            .double(4.2), .double(210), .text("api"), .int(80), .int(70),
            .null, .null, .null, .null, .null, .null, .null, .null, .null, .null
        ]])
        let version = try await database.userVersion()
        XCTAssertEqual(version, 23)
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
        try await createVersion14ChargeSummaryTable(in: database)
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
        try await createVersion14ChargeSummaryTable(in: database)
        try await database.setUserVersion(15)

        try await Migrations.applyAll(to: database)

        let migrated = try await database.rows("SELECT drive_id, distance, duration_min, energy_consumed_net, consumption_net FROM drives_summary;")
        XCTAssertEqual(migrated, [[.int(7), .double(12.5), .int(30), .null, .null]])
        let version = try await database.userVersion()
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
    }

    func testVersion16ChargeSummariesGainOfflinePresentationFieldsWithoutDataLoss() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("""
            CREATE TABLE charges_summary (
              charge_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT,
              charge_energy_added REAL,
              cost REAL,
              schema_version INTEGER NOT NULL DEFAULT 13
            );
            """)
        try await createVersion16DriveSummaryTable(in: database)
        try await database.execute("INSERT INTO charges_summary VALUES (20, 1, 'start', 'end', 12.5, 8.25, 13);")
        try await database.setUserVersion(16)

        try await Migrations.applyAll(to: database)

        let migrated = try await database.rows(
            "SELECT charge_id, charge_energy_added, cost, duration_min, address, latitude, longitude FROM charges_summary;"
        )
        let version = try await database.userVersion()
        XCTAssertEqual(migrated, [[.int(20), .double(12.5), .double(8.25), .null, .null, .null, .null]])
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
        try await assertTask3CurrentSchema(in: database)
    }

    func testVersion17SummariesGainEnergyCycleFieldsWithoutDataLoss() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("""
            CREATE TABLE charges_summary (
              charge_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT,
              charge_energy_added REAL,
              cost REAL,
              schema_version INTEGER NOT NULL DEFAULT 13,
              duration_min INTEGER,
              address TEXT,
              latitude REAL,
              longitude REAL
            );
            """)
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13,
              energy_consumed_net REAL,
              consumption_net REAL,
              energy_source TEXT
            );
            """)
        try await database.execute("INSERT INTO charges_summary VALUES (20, 1, 'start', 'end', 12.5, 8.25, 13, 60, 'Home', 1, 2);")
        try await database.execute("INSERT INTO drives_summary VALUES (10, 1, 'start', 'end', 20, 30, 13, 4.2, 210, 'api');")
        try await database.setUserVersion(17)

        try await Migrations.applyAll(to: database)

        let charge = try await database.rows("SELECT charge_id, charge_energy_used, start_battery_level, end_battery_level, end_rated_range_km FROM charges_summary;")
        let drive = try await database.rows("SELECT drive_id, energy_consumed_net, start_battery_level, end_battery_level FROM drives_summary;")
        let version = try await database.userVersion()
        XCTAssertEqual(charge, [[.int(20), .null, .null, .null, .null]])
        XCTAssertEqual(drive, [[.int(10), .double(4.2), .null, .null]])
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
        try await assertTask3CurrentSchema(in: database)
    }

    func testVersion18DriveSummaryMissingLegacyEnergySourceColumnIsRepaired() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await createVersion18ChargeSummaryTable(in: database)
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13,
              energy_consumed_net REAL,
              consumption_net REAL,
              start_battery_level INTEGER,
              end_battery_level INTEGER
            );
            """)
        try await database.execute("INSERT INTO drives_summary VALUES (10, 1, 'start', 'end', 20, 30, 13, 4.2, 210, 80, 70);")
        try await database.setUserVersion(18)

        try await Migrations.applyAll(to: database)

        let rows = try await database.rows("SELECT drive_id, energy_source FROM drives_summary;")
        let version = try await database.userVersion()
        XCTAssertEqual(rows, [[.int(10), .null]])
        XCTAssertEqual(version, DatabaseSchemaVersion.current)
        try await assertTask3CurrentSchema(in: database)
    }

    func testVersion19UpgradesToSleepIntervalsWithoutLosingRequiredSummaryColumns() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await createVersion18ChargeSummaryTable(in: database)
        try await createVersion19DriveSummaryTable(in: database)
        try await database.setUserVersion(19)

        try await Migrations.applyAll(to: database)

        try await assertTask3CurrentSchema(in: database)
    }

    private func createVersion14ChargeSummaryTable(in database: SQLiteDatabase) async throws {
        try await database.execute("""
            CREATE TABLE charges_summary (
              charge_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT,
              charge_energy_added REAL,
              cost REAL,
              schema_version INTEGER NOT NULL DEFAULT 12
            );
            """)
    }

    private func createVersion16DriveSummaryTable(in database: SQLiteDatabase) async throws {
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13,
              energy_consumed_net REAL,
              consumption_net REAL,
              energy_source TEXT
            );
            """)
    }

    private func createVersion18ChargeSummaryTable(in database: SQLiteDatabase) async throws {
        try await database.execute("""
            CREATE TABLE charges_summary (
              charge_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT,
              charge_energy_added REAL,
              cost REAL,
              schema_version INTEGER NOT NULL DEFAULT 13,
              duration_min INTEGER,
              address TEXT,
              latitude REAL,
              longitude REAL,
              charge_energy_used REAL,
              start_battery_level INTEGER,
              end_battery_level INTEGER,
              start_rated_range_km REAL,
              end_rated_range_km REAL,
              odometer_km REAL
            );
            """)
    }

    private func createVersion19DriveSummaryTable(in database: SQLiteDatabase) async throws {
        try await database.execute("""
            CREATE TABLE drives_summary (
              drive_id INTEGER PRIMARY KEY NOT NULL,
              car_id INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT NOT NULL,
              distance REAL,
              duration_min INTEGER,
              schema_version INTEGER NOT NULL DEFAULT 13,
              energy_consumed_net REAL,
              consumption_net REAL,
              energy_source TEXT,
              start_battery_level INTEGER,
              end_battery_level INTEGER
            );
            """)
    }

    private func assertTask3CurrentSchema(
        in database: SQLiteDatabase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let chargeColumns = Set(try await database.rows("PRAGMA table_info(charges_summary);").compactMap { $0[1].textValue })
        let driveColumns = Set(try await database.rows("PRAGMA table_info(drives_summary);").compactMap { $0[1].textValue })
        let tables = try await database.tableNames()
        let version = try await database.userVersion()
        let requiredChargeColumns: Set<String> = [
            "duration_min", "address", "latitude", "longitude", "charge_energy_used",
            "start_battery_level", "end_battery_level", "start_rated_range_km",
            "end_rated_range_km", "odometer_km"
        ]
        let requiredDriveColumns: Set<String> = [
            "energy_consumed_net", "consumption_net", "energy_source",
            "start_battery_level", "end_battery_level"
        ]

        XCTAssertTrue(requiredChargeColumns.isSubset(of: chargeColumns), file: file, line: line)
        XCTAssertTrue(requiredDriveColumns.isSubset(of: driveColumns), file: file, line: line)
        XCTAssertTrue(tables.contains("sleep_intervals"), file: file, line: line)
        XCTAssertEqual(version, 23, file: file, line: line)
    }
}
