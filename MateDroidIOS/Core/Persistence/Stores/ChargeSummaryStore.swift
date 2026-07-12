import Foundation

public protocol ChargeSummaryStoring: Sendable {
    func upsertAll(_ records: [ChargeSummaryRecord]) async throws
    func unprocessedChargeIds(carId: Int, schemaVersion: Int) async throws -> [Int]
}

public struct ChargeSummaryStore: ChargeSummaryStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertAll(_ records: [ChargeSummaryRecord]) async throws {
        for record in records {
            try await database.run(
                """
                INSERT INTO charges_summary
                (charge_id, car_id, start_date, end_date, charge_energy_added, cost, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(charge_id) DO UPDATE SET
                  car_id = excluded.car_id,
                  start_date = excluded.start_date,
                  end_date = excluded.end_date,
                  charge_energy_added = excluded.charge_energy_added,
                  cost = excluded.cost;
                """,
                bindings: [
                    .int(record.chargeId),
                    .int(record.carId),
                    .text(record.startDate),
                    record.endDate.map(SQLiteValue.text) ?? .null,
                    record.chargeEnergyAdded.map(SQLiteValue.double) ?? .null,
                    record.cost.map(SQLiteValue.double) ?? .null,
                    .int(record.schemaVersion)
                ]
            )
        }
    }

    public func markProcessed(ids: [Int], schemaVersion: Int = SchemaVersion.current) async throws {
        for id in ids {
            try await database.run(
                "UPDATE charges_summary SET schema_version = ? WHERE charge_id = ?;",
                bindings: [.int(schemaVersion), .int(id)]
            )
        }
    }

    public func unprocessedChargeIds(carId: Int, schemaVersion: Int = SchemaVersion.current) async throws -> [Int] {
        try await database.intValues(
            "SELECT charge_id FROM charges_summary WHERE car_id = ? AND schema_version != ? ORDER BY start_date;",
            bindings: [.int(carId), .int(schemaVersion)]
        )
    }
}
