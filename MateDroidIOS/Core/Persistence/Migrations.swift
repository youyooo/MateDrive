import Foundation

public enum Migrations {
    public static func applyAll(to database: SQLiteDatabase) async throws {
        let currentVersion = try await database.userVersion()
        for migration in all where migration.version > currentVersion {
            try await database.execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                for statement in migration.statements {
                    try await database.execute(statement)
                }
                try await database.setUserVersion(migration.version)
                try await database.execute("COMMIT;")
            } catch {
                try? await database.execute("ROLLBACK;")
                throw error
            }
        }
    }

    public static let all: [Migration] = [
        Migration(
            version: 14,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS sync_state (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT,
                  updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS drives_summary (
                  drive_id INTEGER PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  start_date TEXT NOT NULL,
                  end_date TEXT NOT NULL,
                  distance REAL NOT NULL,
                  duration_min INTEGER NOT NULL,
                  schema_version INTEGER NOT NULL DEFAULT 12
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS charges_summary (
                  charge_id INTEGER PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  start_date TEXT NOT NULL,
                  end_date TEXT,
                  charge_energy_added REAL,
                  cost REAL,
                  schema_version INTEGER NOT NULL DEFAULT 12
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS drive_detail_aggregates (
                  drive_id INTEGER PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  payload_json TEXT NOT NULL,
                  schema_version INTEGER NOT NULL DEFAULT 12
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS charge_detail_aggregates (
                  charge_id INTEGER PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  payload_json TEXT NOT NULL,
                  schema_version INTEGER NOT NULL DEFAULT 12
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS charge_cost_overrides (
                  charge_id INTEGER NOT NULL,
                  car_id INTEGER NOT NULL,
                  cost REAL NOT NULL,
                  updated_at TEXT NOT NULL,
                  PRIMARY KEY(charge_id, car_id)
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS teslamate_capabilities (
                  server_key TEXT NOT NULL,
                  car_id INTEGER NOT NULL,
                  capability TEXT NOT NULL,
                  status_json TEXT NOT NULL,
                  connection_issue_json TEXT,
                  api_version TEXT,
                  mt_api_version TEXT,
                  build_info TEXT,
                  checked_at TEXT NOT NULL,
                  last_successful_check_at TEXT,
                  PRIMARY KEY(server_key, car_id, capability)
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS geocode_cache (
                  cache_key TEXT PRIMARY KEY NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  payload_json TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS geocode_queue (
                  cache_key TEXT PRIMARY KEY NOT NULL,
                  latitude REAL NOT NULL,
                  longitude REAL NOT NULL,
                  created_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS geocode_progress (
                  car_id INTEGER PRIMARY KEY NOT NULL,
                  last_processed_at TEXT
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS sentry_alert_log (
                  event_id TEXT PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  occurred_at TEXT NOT NULL,
                  payload_json TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS trip_route_cache (
                  cache_key TEXT PRIMARY KEY NOT NULL,
                  payload_json TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS trip_country_cache (
                  cache_key TEXT PRIMARY KEY NOT NULL,
                  payload_json TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS saved_trips (
                  trip_id TEXT PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  name TEXT NOT NULL,
                  start_date TEXT NOT NULL,
                  end_date TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS saved_trip_legs (
                  leg_id TEXT PRIMARY KEY NOT NULL,
                  trip_id TEXT NOT NULL,
                  sequence INTEGER NOT NULL,
                  payload_json TEXT NOT NULL,
                  FOREIGN KEY(trip_id) REFERENCES saved_trips(trip_id) ON DELETE CASCADE
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS saved_trip_consumed_fingerprints (
                  trip_id TEXT NOT NULL,
                  fingerprint TEXT NOT NULL,
                  PRIMARY KEY(trip_id, fingerprint),
                  FOREIGN KEY(trip_id) REFERENCES saved_trips(trip_id) ON DELETE CASCADE
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS charge_pricing_audit_batches (
                  batch_id TEXT PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  created_at TEXT NOT NULL,
                  currency_code TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS charge_pricing_audit_items (
                  batch_id TEXT NOT NULL,
                  sequence INTEGER NOT NULL,
                  charge_id INTEGER NOT NULL,
                  start_date TEXT NOT NULL,
                  rule_id TEXT NOT NULL,
                  rule_name TEXT NOT NULL,
                  previous_cost REAL,
                  target_cost REAL NOT NULL,
                  write_succeeded INTEGER NOT NULL,
                  write_message TEXT,
                  rollback_attempted INTEGER NOT NULL,
                  restored_cost REAL,
                  rollback_succeeded INTEGER,
                  rollback_message TEXT,
                  PRIMARY KEY(batch_id, charge_id),
                  FOREIGN KEY(batch_id) REFERENCES charge_pricing_audit_batches(batch_id) ON DELETE CASCADE
                );
                """,
                """
                CREATE INDEX IF NOT EXISTS charge_pricing_audit_batches_car_date
                ON charge_pricing_audit_batches(car_id, created_at DESC);
                """
            ]
        ),
        Migration(
            version: 15,
            statements: [
                """
                CREATE TABLE drives_summary_v15 (
                  drive_id INTEGER PRIMARY KEY NOT NULL,
                  car_id INTEGER NOT NULL,
                  start_date TEXT NOT NULL,
                  end_date TEXT NOT NULL,
                  distance REAL,
                  duration_min INTEGER,
                  schema_version INTEGER NOT NULL DEFAULT 13
                );
                """,
                """
                INSERT INTO drives_summary_v15
                  (drive_id, car_id, start_date, end_date, distance, duration_min, schema_version)
                SELECT drive_id, car_id, start_date, end_date, distance, duration_min, schema_version
                FROM drives_summary;
                """,
                "DROP TABLE drives_summary;",
                "ALTER TABLE drives_summary_v15 RENAME TO drives_summary;"
            ]
        ),
        Migration(
            version: 16,
            statements: [
                "ALTER TABLE drives_summary ADD COLUMN energy_consumed_net REAL;",
                "ALTER TABLE drives_summary ADD COLUMN consumption_net REAL;",
                "ALTER TABLE drives_summary ADD COLUMN energy_source TEXT;"
            ]
        )
    ]
}
