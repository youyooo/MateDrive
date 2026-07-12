import Foundation

public protocol ChargePricingAggregateProviding: Sendable {
    func chargePricingAggregates(carId: Int) async throws -> [Int: ChargeDetailPricingAggregate]
}

public struct EmptyChargePricingAggregateStore: ChargePricingAggregateProviding {
    public init() {}

    public func chargePricingAggregates(carId _: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        [:]
    }
}

public struct DatabaseBackedChargePricingAggregateStore: ChargePricingAggregateProviding {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func chargePricingAggregates(carId: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        let database = try await databaseProvider.database()
        return try await AggregateStore(database: database).chargePricingAggregates(carId: carId)
    }
}

public struct AggregateStore: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertDriveAggregate(_ record: DriveDetailAggregateRecord) async throws {
        try await database.run(
            """
            INSERT OR REPLACE INTO drive_detail_aggregates
            (drive_id, car_id, payload_json, schema_version)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [.int(record.driveId), .int(record.carId), .text(record.payloadJSON), .int(record.schemaVersion)]
        )
    }

    public func upsertChargeAggregate(_ record: ChargeDetailAggregateRecord) async throws {
        try await database.run(
            """
            INSERT OR REPLACE INTO charge_detail_aggregates
            (charge_id, car_id, payload_json, schema_version)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [.int(record.chargeId), .int(record.carId), .text(record.payloadJSON), .int(record.schemaVersion)]
        )
    }

    public func chargePricingAggregates(carId: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        let rows = try await database.rows(
            """
            SELECT charge_id, payload_json
            FROM charge_detail_aggregates
            WHERE car_id = ? AND schema_version = ?;
            """,
            bindings: [.int(carId), .int(SchemaVersion.current)]
        )

        return rows.reduce(into: [Int: ChargeDetailPricingAggregate]()) { partialResult, row in
            guard row.count >= 2,
                  let chargeId = row[0].intValue,
                  let payloadJSON = row[1].textValue,
                  let data = payloadJSON.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(ChargeAggregatePricingPayload.self, from: data)
            else {
                return
            }
            let isDc = payload.isFastCharger ?? payload.chargerPhases.map { $0 == 0 }
            partialResult[chargeId] = ChargeDetailPricingAggregate(
                chargeId: chargeId,
                isDc: isDc,
                energySamples: payload.energySamples.map {
                    ChargePricingEnergySample(date: $0.date, cumulativeEnergyAddedKWh: $0.chargeEnergyAdded)
                },
                chargerIdentity: isDc.map {
                    ChargeStatsCalculator.chargerIdentity(isDc: $0, fastChargerBrand: payload.fastChargerBrand)
                }
            )
        }
    }
}

private struct ChargeAggregatePricingPayload: Decodable {
    let isFastCharger: Bool?
    let fastChargerBrand: String?
    let connectorType: String?
    let chargerPhases: Int?
    let energySamples: [ChargeAggregateEnergySample]

    private enum CodingKeys: String, CodingKey {
        case isFastCharger
        case fastChargerBrand
        case connectorType
        case chargerPhases
        case energySamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFastCharger = try container.decodeIfPresent(Bool.self, forKey: .isFastCharger)
        fastChargerBrand = try container.decodeIfPresent(String.self, forKey: .fastChargerBrand)
        connectorType = try container.decodeIfPresent(String.self, forKey: .connectorType)
        chargerPhases = try container.decodeIfPresent(Int.self, forKey: .chargerPhases)
        energySamples = try container.decodeIfPresent([ChargeAggregateEnergySample].self, forKey: .energySamples) ?? []
    }
}

private struct ChargeAggregateEnergySample: Decodable {
    let date: String?
    let chargeEnergyAdded: Double?
}
