import Foundation

public protocol ChargeSummaryStoring: Sendable {
    func upsertAll(_ records: [ChargeSummaryRecord]) async throws
    func records(carId: Int) async throws -> [ChargeSummaryRecord]
    func unprocessedChargeIds(carId: Int, schemaVersion: Int) async throws -> [Int]
}

public struct ChargeSummaryStore: ChargeSummaryStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertAll(_ records: [ChargeSummaryRecord]) async throws {
        guard !records.isEmpty else { return }
        let commands = records.map { record in
            SQLiteCommand(
                """
                INSERT INTO charges_summary
                (charge_id, car_id, start_date, end_date, charge_energy_added, cost,
                 duration_min, address, latitude, longitude, charge_energy_used,
                 start_battery_level, end_battery_level, start_rated_range_km,
                 end_rated_range_km, odometer_km, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(charge_id) DO UPDATE SET
                  car_id = excluded.car_id,
                  start_date = excluded.start_date,
                  end_date = COALESCE(excluded.end_date, charges_summary.end_date),
                  charge_energy_added = COALESCE(excluded.charge_energy_added, charges_summary.charge_energy_added),
                  cost = excluded.cost,
                  duration_min = COALESCE(excluded.duration_min, charges_summary.duration_min),
                  address = COALESCE(excluded.address, charges_summary.address),
                  latitude = COALESCE(excluded.latitude, charges_summary.latitude),
                  longitude = COALESCE(excluded.longitude, charges_summary.longitude),
                  charge_energy_used = COALESCE(excluded.charge_energy_used, charges_summary.charge_energy_used),
                  start_battery_level = COALESCE(excluded.start_battery_level, charges_summary.start_battery_level),
                  end_battery_level = COALESCE(excluded.end_battery_level, charges_summary.end_battery_level),
                  start_rated_range_km = COALESCE(excluded.start_rated_range_km, charges_summary.start_rated_range_km),
                  end_rated_range_km = COALESCE(excluded.end_rated_range_km, charges_summary.end_rated_range_km),
                  odometer_km = COALESCE(excluded.odometer_km, charges_summary.odometer_km)
                WHERE charges_summary.car_id IS NOT excluded.car_id
                   OR charges_summary.start_date IS NOT excluded.start_date
                   OR (excluded.end_date IS NOT NULL AND charges_summary.end_date IS NOT excluded.end_date)
                   OR (excluded.charge_energy_added IS NOT NULL AND charges_summary.charge_energy_added IS NOT excluded.charge_energy_added)
                   OR charges_summary.cost IS NOT excluded.cost
                   OR (excluded.duration_min IS NOT NULL AND charges_summary.duration_min IS NOT excluded.duration_min)
                   OR (excluded.address IS NOT NULL AND charges_summary.address IS NOT excluded.address)
                   OR (excluded.latitude IS NOT NULL AND charges_summary.latitude IS NOT excluded.latitude)
                   OR (excluded.longitude IS NOT NULL AND charges_summary.longitude IS NOT excluded.longitude)
                   OR (excluded.charge_energy_used IS NOT NULL AND charges_summary.charge_energy_used IS NOT excluded.charge_energy_used)
                   OR (excluded.start_battery_level IS NOT NULL AND charges_summary.start_battery_level IS NOT excluded.start_battery_level)
                   OR (excluded.end_battery_level IS NOT NULL AND charges_summary.end_battery_level IS NOT excluded.end_battery_level)
                   OR (excluded.start_rated_range_km IS NOT NULL AND charges_summary.start_rated_range_km IS NOT excluded.start_rated_range_km)
                   OR (excluded.end_rated_range_km IS NOT NULL AND charges_summary.end_rated_range_km IS NOT excluded.end_rated_range_km)
                   OR (excluded.odometer_km IS NOT NULL AND charges_summary.odometer_km IS NOT excluded.odometer_km);
                """,
                bindings: [
                    .int(record.chargeId),
                    .int(record.carId),
                    .text(record.startDate),
                    record.endDate.map(SQLiteValue.text) ?? .null,
                    record.chargeEnergyAdded.map(SQLiteValue.double) ?? .null,
                    record.cost.map(SQLiteValue.double) ?? .null,
                    record.durationMin.map(SQLiteValue.int) ?? .null,
                    record.address.map(SQLiteValue.text) ?? .null,
                    record.latitude.map(SQLiteValue.double) ?? .null,
                    record.longitude.map(SQLiteValue.double) ?? .null,
                    record.chargeEnergyUsed.map(SQLiteValue.double) ?? .null,
                    record.startBatteryLevel.map(SQLiteValue.int) ?? .null,
                    record.endBatteryLevel.map(SQLiteValue.int) ?? .null,
                    record.startRatedRangeKm.map(SQLiteValue.double) ?? .null,
                    record.endRatedRangeKm.map(SQLiteValue.double) ?? .null,
                    record.odometerKm.map(SQLiteValue.double) ?? .null,
                    .int(record.schemaVersion)
                ]
            )
        }
        try await database.performTransaction(commands)
    }

    public func records(carId: Int) async throws -> [ChargeSummaryRecord] {
        let rows = try await database.rows(
            """
            SELECT charge_id, car_id, start_date, end_date, charge_energy_added, cost,
                   duration_min, address, latitude, longitude, charge_energy_used,
                   start_battery_level, end_battery_level, start_rated_range_km,
                   end_rated_range_km, odometer_km, schema_version
            FROM charges_summary
            WHERE car_id = ?
            ORDER BY start_date DESC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap { row in
            guard row.count == 17,
                  let chargeId = row[0].intValue,
                  let rowCarId = row[1].intValue,
                  let startDate = row[2].textValue,
                  let schemaVersion = row[16].intValue
            else { return nil }
            return ChargeSummaryRecord(
                chargeId: chargeId,
                carId: rowCarId,
                startDate: startDate,
                endDate: row[3].textValue,
                chargeEnergyAdded: row[4].doubleValue,
                cost: row[5].doubleValue,
                durationMin: row[6].intValue,
                address: row[7].textValue,
                latitude: row[8].doubleValue,
                longitude: row[9].doubleValue,
                chargeEnergyUsed: row[10].doubleValue,
                startBatteryLevel: row[11].intValue,
                endBatteryLevel: row[12].intValue,
                startRatedRangeKm: row[13].doubleValue,
                endRatedRangeKm: row[14].doubleValue,
                odometerKm: row[15].doubleValue,
                schemaVersion: schemaVersion
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

    public func updateTelemetry(
        chargeId: Int,
        chargeEnergyAdded: Double?,
        chargeEnergyUsed: Double?,
        startBatteryLevel: Int?,
        endBatteryLevel: Int?,
        startRatedRangeKm: Double?,
        endRatedRangeKm: Double?,
        odometerKm: Double?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async throws {
        try await database.run(
            """
            UPDATE charges_summary
            SET charge_energy_added = COALESCE(?, charge_energy_added),
                charge_energy_used = COALESCE(?, charge_energy_used),
                start_battery_level = COALESCE(?, start_battery_level),
                end_battery_level = COALESCE(?, end_battery_level),
                start_rated_range_km = COALESCE(?, start_rated_range_km),
                end_rated_range_km = COALESCE(?, end_rated_range_km),
                odometer_km = COALESCE(?, odometer_km),
                latitude = COALESCE(?, latitude),
                longitude = COALESCE(?, longitude)
            WHERE charge_id = ?;
            """,
            bindings: [
                chargeEnergyAdded.map(SQLiteValue.double) ?? .null,
                chargeEnergyUsed.map(SQLiteValue.double) ?? .null,
                startBatteryLevel.map(SQLiteValue.int) ?? .null,
                endBatteryLevel.map(SQLiteValue.int) ?? .null,
                startRatedRangeKm.map(SQLiteValue.double) ?? .null,
                endRatedRangeKm.map(SQLiteValue.double) ?? .null,
                odometerKm.map(SQLiteValue.double) ?? .null,
                latitude.map(SQLiteValue.double) ?? .null,
                longitude.map(SQLiteValue.double) ?? .null,
                .int(chargeId)
            ]
        )
    }

    public func unprocessedChargeIds(carId: Int, schemaVersion: Int = SchemaVersion.current) async throws -> [Int] {
        try await database.intValues(
            "SELECT charge_id FROM charges_summary WHERE car_id = ? AND schema_version != ? ORDER BY start_date DESC, charge_id DESC;",
            bindings: [.int(carId), .int(schemaVersion)]
        )
    }
}
