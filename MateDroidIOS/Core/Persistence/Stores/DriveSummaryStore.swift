import Foundation

public protocol DriveSummaryStoring: Sendable {
    func upsertAll(_ records: [DriveSummaryRecord]) async throws
    func records(carId: Int) async throws -> [DriveSummaryRecord]
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
                (drive_id, car_id, start_date, end_date, distance, duration_min, energy_consumed_net, consumption_net, energy_source, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(drive_id) DO UPDATE SET
                  car_id = excluded.car_id,
                  start_date = excluded.start_date,
                  end_date = excluded.end_date,
                  distance = excluded.distance,
                  duration_min = excluded.duration_min,
                  energy_consumed_net = excluded.energy_consumed_net,
                  consumption_net = excluded.consumption_net,
                  energy_source = excluded.energy_source;
                """,
                bindings: [
                    .int(record.driveId),
                    .int(record.carId),
                    .text(record.startDate),
                    .text(record.endDate),
                    record.distance.map(SQLiteValue.double) ?? .null,
                    record.durationMin.map(SQLiteValue.int) ?? .null,
                    record.energyConsumedNet.map(SQLiteValue.double) ?? .null,
                    record.consumptionNet.map(SQLiteValue.double) ?? .null,
                    record.energySource.map(SQLiteValue.text) ?? .null,
                    .int(record.schemaVersion)
                ]
            )
        }
    }

    public func records(carId: Int) async throws -> [DriveSummaryRecord] {
        let rows = try await database.rows(
            """
            SELECT drive_id, car_id, start_date, end_date, distance, duration_min,
                   energy_consumed_net, consumption_net, energy_source, schema_version
            FROM drives_summary
            WHERE car_id = ?
            ORDER BY start_date DESC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap { row in
            guard row.count == 10,
                  let driveId = row[0].intValue,
                  let rowCarId = row[1].intValue,
                  let startDate = row[2].textValue,
                  let endDate = row[3].textValue,
                  let schemaVersion = row[9].intValue
            else { return nil }
            return DriveSummaryRecord(
                driveId: driveId,
                carId: rowCarId,
                startDate: startDate,
                endDate: endDate,
                distance: row[4].doubleValue,
                durationMin: row[5].intValue,
                energyConsumedNet: row[6].doubleValue,
                consumptionNet: row[7].doubleValue,
                energySource: row[8].textValue,
                schemaVersion: schemaVersion
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
