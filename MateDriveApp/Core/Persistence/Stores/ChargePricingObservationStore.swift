import Foundation

public protocol ChargePricingObservationStoring: Sendable {
    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation]
    func save(_ value: ChargePricingObservation) async throws
    func remove(id: String) async throws
    func removeAll() async throws
}

public struct ChargePricingObservationStore: ChargePricingObservationStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] {
        let rows = try await database.rows(
            """
            SELECT payload_json
            FROM charge_pricing_observations
            WHERE car_id = ? AND station_key = ?
            ORDER BY confirmed_at DESC, observation_id ASC;
            """,
            bindings: [.int(carId), .text(stationKey)]
        )
        return rows.compactMap { row in
            guard let payload = row.first?.textValue,
                  let value = try? SmartActivityPersistenceCoding.decode(
                      ChargePricingObservation.self,
                      from: payload
                  ),
                  value.carId == carId,
                  value.stationKey == stationKey
            else { return nil }
            return value
        }
    }

    public func save(_ value: ChargePricingObservation) async throws {
        let payload = try SmartActivityPersistenceCoding.encode(value)
        try await database.run(
            """
            INSERT INTO charge_pricing_observations
            (observation_id, car_id, charge_id, station_key, scope, payload_json, confirmed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(observation_id) DO UPDATE SET
              car_id = excluded.car_id,
              charge_id = excluded.charge_id,
              station_key = excluded.station_key,
              scope = excluded.scope,
              payload_json = excluded.payload_json,
              confirmed_at = excluded.confirmed_at;
            """,
            bindings: [
                .text(value.id),
                .int(value.carId),
                .int(value.chargeId),
                .text(value.stationKey),
                .text(value.scope.rawValue),
                .text(payload),
                .text(SmartActivityPersistenceCoding.dateString(value.confirmedAt))
            ]
        )
    }

    public func remove(id: String) async throws {
        try await database.run(
            "DELETE FROM charge_pricing_observations WHERE observation_id = ?;",
            bindings: [.text(id)]
        )
    }

    public func removeAll() async throws {
        try await database.run("DELETE FROM charge_pricing_observations;")
    }
}

public struct DatabaseBackedChargePricingObservationStore: ChargePricingObservationStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] {
        try await ChargePricingObservationStore(database: databaseProvider.database())
            .observations(carId: carId, stationKey: stationKey)
    }

    public func save(_ value: ChargePricingObservation) async throws {
        try await ChargePricingObservationStore(database: databaseProvider.database()).save(value)
    }

    public func remove(id: String) async throws {
        try await ChargePricingObservationStore(database: databaseProvider.database()).remove(id: id)
    }

    public func removeAll() async throws {
        try await ChargePricingObservationStore(database: databaseProvider.database()).removeAll()
    }
}
