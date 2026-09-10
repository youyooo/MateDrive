import Foundation

public protocol DriveSummaryStoring: Sendable {
    func upsertAll(_ records: [DriveSummaryRecord]) async throws
    func records(carId: Int) async throws -> [DriveSummaryRecord]
    func unprocessedDriveIds(carId: Int, schemaVersion: Int) async throws -> [Int]
    func updateEnergy(driveId: Int, energyConsumedNet: Double?, consumptionNet: Double?, source: String?) async throws
}

public struct DriveSummaryStore: DriveSummaryStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertAll(_ records: [DriveSummaryRecord]) async throws {
        guard !records.isEmpty else { return }
        let commands = records.map { record in
            SQLiteCommand(
                """
                INSERT INTO drives_summary
                (drive_id, car_id, start_date, end_date, distance, duration_min, energy_consumed_net, consumption_net,
                 energy_source, start_battery_level, end_battery_level, start_rated_range_km,
                 end_rated_range_km, start_address, end_address, speed_avg, outside_temp_avg,
                 route_fingerprint_json, climate_on_fraction, elevation_gain_m, elevation_loss_m, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(drive_id) DO UPDATE SET
                  car_id = excluded.car_id,
                  start_date = excluded.start_date,
                  end_date = excluded.end_date,
                  distance = COALESCE(excluded.distance, drives_summary.distance),
                  duration_min = COALESCE(excluded.duration_min, drives_summary.duration_min),
                  energy_consumed_net = COALESCE(excluded.energy_consumed_net, drives_summary.energy_consumed_net),
                  consumption_net = COALESCE(excluded.consumption_net, drives_summary.consumption_net),
                  energy_source = COALESCE(excluded.energy_source, drives_summary.energy_source),
                  start_battery_level = COALESCE(excluded.start_battery_level, drives_summary.start_battery_level),
                  end_battery_level = COALESCE(excluded.end_battery_level, drives_summary.end_battery_level),
                  start_rated_range_km = COALESCE(excluded.start_rated_range_km, drives_summary.start_rated_range_km),
                  end_rated_range_km = COALESCE(excluded.end_rated_range_km, drives_summary.end_rated_range_km),
                  start_address = COALESCE(excluded.start_address, drives_summary.start_address),
                  end_address = COALESCE(excluded.end_address, drives_summary.end_address),
                  speed_avg = COALESCE(excluded.speed_avg, drives_summary.speed_avg),
                  outside_temp_avg = COALESCE(excluded.outside_temp_avg, drives_summary.outside_temp_avg),
                  route_fingerprint_json = COALESCE(excluded.route_fingerprint_json, drives_summary.route_fingerprint_json),
                  climate_on_fraction = COALESCE(excluded.climate_on_fraction, drives_summary.climate_on_fraction),
                  elevation_gain_m = COALESCE(excluded.elevation_gain_m, drives_summary.elevation_gain_m),
                  elevation_loss_m = COALESCE(excluded.elevation_loss_m, drives_summary.elevation_loss_m)
                WHERE drives_summary.car_id IS NOT excluded.car_id
                   OR drives_summary.start_date IS NOT excluded.start_date
                   OR drives_summary.end_date IS NOT excluded.end_date
                   OR (excluded.distance IS NOT NULL AND drives_summary.distance IS NOT excluded.distance)
                   OR (excluded.duration_min IS NOT NULL AND drives_summary.duration_min IS NOT excluded.duration_min)
                   OR (excluded.energy_consumed_net IS NOT NULL AND drives_summary.energy_consumed_net IS NOT excluded.energy_consumed_net)
                   OR (excluded.consumption_net IS NOT NULL AND drives_summary.consumption_net IS NOT excluded.consumption_net)
                   OR (excluded.energy_source IS NOT NULL AND drives_summary.energy_source IS NOT excluded.energy_source)
                   OR (excluded.start_battery_level IS NOT NULL AND drives_summary.start_battery_level IS NOT excluded.start_battery_level)
                   OR (excluded.end_battery_level IS NOT NULL AND drives_summary.end_battery_level IS NOT excluded.end_battery_level)
                   OR (excluded.start_rated_range_km IS NOT NULL AND drives_summary.start_rated_range_km IS NOT excluded.start_rated_range_km)
                   OR (excluded.end_rated_range_km IS NOT NULL AND drives_summary.end_rated_range_km IS NOT excluded.end_rated_range_km)
                   OR (excluded.start_address IS NOT NULL AND drives_summary.start_address IS NOT excluded.start_address)
                   OR (excluded.end_address IS NOT NULL AND drives_summary.end_address IS NOT excluded.end_address)
                   OR (excluded.speed_avg IS NOT NULL AND drives_summary.speed_avg IS NOT excluded.speed_avg)
                   OR (excluded.outside_temp_avg IS NOT NULL AND drives_summary.outside_temp_avg IS NOT excluded.outside_temp_avg)
                   OR (excluded.route_fingerprint_json IS NOT NULL AND drives_summary.route_fingerprint_json IS NOT excluded.route_fingerprint_json)
                   OR (excluded.climate_on_fraction IS NOT NULL AND drives_summary.climate_on_fraction IS NOT excluded.climate_on_fraction)
                   OR (excluded.elevation_gain_m IS NOT NULL AND drives_summary.elevation_gain_m IS NOT excluded.elevation_gain_m)
                   OR (excluded.elevation_loss_m IS NOT NULL AND drives_summary.elevation_loss_m IS NOT excluded.elevation_loss_m);
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
                    record.startBatteryLevel.map(SQLiteValue.int) ?? .null,
                    record.endBatteryLevel.map(SQLiteValue.int) ?? .null,
                    record.startRatedRangeKm.map(SQLiteValue.double) ?? .null,
                    record.endRatedRangeKm.map(SQLiteValue.double) ?? .null,
                    record.startAddress.map(SQLiteValue.text) ?? .null,
                    record.endAddress.map(SQLiteValue.text) ?? .null,
                    record.speedAvg.map(SQLiteValue.double) ?? .null,
                    record.outsideTempAvg.map(SQLiteValue.double) ?? .null,
                    record.routeFingerprintJSON.map(SQLiteValue.text) ?? .null,
                    record.climateOnFraction.map(SQLiteValue.double) ?? .null,
                    record.elevationGainM.map(SQLiteValue.double) ?? .null,
                    record.elevationLossM.map(SQLiteValue.double) ?? .null,
                    .int(record.schemaVersion)
                ]
            )
        }
        try await database.performTransaction(commands)
    }

    public func records(carId: Int) async throws -> [DriveSummaryRecord] {
        let rows = try await database.rows(
            """
            SELECT drive_id, car_id, start_date, end_date, distance, duration_min,
                   energy_consumed_net, consumption_net, energy_source,
                   start_battery_level, end_battery_level, start_rated_range_km,
                   end_rated_range_km, start_address, end_address, speed_avg, outside_temp_avg,
                   route_fingerprint_json, climate_on_fraction, elevation_gain_m, elevation_loss_m, schema_version
            FROM drives_summary
            WHERE car_id = ?
            ORDER BY start_date DESC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap { row in
            guard row.count == 22,
                  let driveId = row[0].intValue,
                  let rowCarId = row[1].intValue,
                  let startDate = row[2].textValue,
                  let endDate = row[3].textValue,
                  let schemaVersion = row[21].intValue
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
                startBatteryLevel: row[9].intValue,
                endBatteryLevel: row[10].intValue,
                startRatedRangeKm: row[11].doubleValue,
                endRatedRangeKm: row[12].doubleValue,
                startAddress: row[13].textValue,
                endAddress: row[14].textValue,
                speedAvg: row[15].doubleValue,
                outsideTempAvg: row[16].doubleValue,
                routeFingerprintJSON: row[17].textValue,
                climateOnFraction: row[18].doubleValue,
                elevationGainM: row[19].doubleValue,
                elevationLossM: row[20].doubleValue,
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

    public func updateEnergy(
        driveId: Int,
        energyConsumedNet: Double?,
        consumptionNet: Double?,
        source: String?
    ) async throws {
        guard energyConsumedNet != nil || consumptionNet != nil else { return }
        try await database.run(
            """
            UPDATE drives_summary
            SET energy_consumed_net = COALESCE(?, energy_consumed_net),
                consumption_net = COALESCE(?, consumption_net),
                energy_source = COALESCE(?, energy_source)
            WHERE drive_id = ?;
            """,
            bindings: [
                energyConsumedNet.map(SQLiteValue.double) ?? .null,
                consumptionNet.map(SQLiteValue.double) ?? .null,
                source.map(SQLiteValue.text) ?? .null,
                .int(driveId)
            ]
        )
    }

    public func unprocessedDriveIds(carId: Int, schemaVersion: Int = SchemaVersion.current) async throws -> [Int] {
        try await database.intValues(
            "SELECT drive_id FROM drives_summary WHERE car_id = ? AND schema_version != ? ORDER BY start_date DESC, drive_id DESC;",
            bindings: [.int(carId), .int(schemaVersion)]
        )
    }
}
