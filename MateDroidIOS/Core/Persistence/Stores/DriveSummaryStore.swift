import Foundation

public protocol DriveSummaryStoring: Sendable {
    func upsertAll(_ records: [DriveSummaryRecord]) async throws
    func unprocessedDriveIds(carId: Int, schemaVersion: Int) async throws -> [Int]
}

public struct DriveSummaryStore: DriveSummaryStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertAll(_ records: [DriveSummaryRecord]) async throws {
        for record in records {
            try await database.run(
                """
                INSERT INTO drives_summary
                (drive_id, car_id, start_date, end_date, distance, duration_min, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(drive_id) DO UPDATE SET
                  car_id = excluded.car_id,
                  start_date = excluded.start_date,
                  end_date = excluded.end_date,
                  distance = excluded.distance,
                  duration_min = excluded.duration_min;
                """,
                bindings: [
                    .int(record.driveId),
                    .int(record.carId),
                    .text(record.startDate),
                    .text(record.endDate),
                    record.distance.map(SQLiteValue.double) ?? .null,
                    record.durationMin.map(SQLiteValue.int) ?? .null,
                    .int(record.schemaVersion)
                ]
            )
        }
    }

    public func markProcessed(ids: [Int], schemaVersion: Int = SchemaVersion.current) async throws {
        for id in ids {
            try await database.run(
                "UPDATE drives_summary SET schema_version = ? WHERE drive_id = ?;",
                bindings: [.int(schemaVersion), .int(id)]
            )
        }
    }

    public func unprocessedDriveIds(carId: Int, schemaVersion: Int = SchemaVersion.current) async throws -> [Int] {
        try await database.intValues(
            "SELECT drive_id FROM drives_summary WHERE car_id = ? AND schema_version != ? ORDER BY start_date;",
            bindings: [.int(carId), .int(schemaVersion)]
        )
    }
}
