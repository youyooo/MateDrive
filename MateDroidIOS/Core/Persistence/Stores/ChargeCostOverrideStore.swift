import Foundation

public extension Notification.Name {
    static let chargeCostOverrideDidChange = Notification.Name("ChargeCostOverrideDidChange")
}

public protocol ChargeCostOverriding: Sendable {
    func costOverrides(carId: Int) async throws -> [Int: Double]
    func costOverride(carId: Int, chargeId: Int) async throws -> Double?
    func saveCostOverride(carId: Int, chargeId: Int, cost: Double?) async throws
}

public enum ChargeCostOverrideValidationError: LocalizedError, Sendable {
    case invalidCost

    public var errorDescription: String? {
        switch self {
        case .invalidCost:
            return "Charge cost must be zero or greater."
        }
    }
}

public struct EmptyChargeCostOverrideStore: ChargeCostOverriding {
    public init() {}

    public func costOverrides(carId _: Int) async throws -> [Int: Double] {
        [:]
    }

    public func costOverride(carId _: Int, chargeId _: Int) async throws -> Double? {
        nil
    }

    public func saveCostOverride(carId _: Int, chargeId _: Int, cost: Double?) async throws {
        try Self.validate(cost)
    }

    private static func validate(_ cost: Double?) throws {
        guard let cost else {
            return
        }
        guard cost.isFinite, cost >= 0 else {
            throw ChargeCostOverrideValidationError.invalidCost
        }
    }
}

public struct DatabaseBackedChargeCostOverrideStore: ChargeCostOverriding {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func costOverrides(carId: Int) async throws -> [Int: Double] {
        let database = try await databaseProvider.database()
        let rows = try await database.rows(
            """
            SELECT charge_id, cost
            FROM charge_cost_overrides
            WHERE car_id = ?;
            """,
            bindings: [.int(carId)]
        )

        return rows.reduce(into: [Int: Double]()) { partialResult, row in
            guard row.count >= 2,
                  let chargeId = row[0].intValue,
                  let cost = row[1].doubleValue
            else {
                return
            }
            partialResult[chargeId] = cost
        }
    }

    public func costOverride(carId: Int, chargeId: Int) async throws -> Double? {
        let database = try await databaseProvider.database()
        return try await database.rows(
            """
            SELECT cost
            FROM charge_cost_overrides
            WHERE car_id = ? AND charge_id = ?
            LIMIT 1;
            """,
            bindings: [.int(carId), .int(chargeId)]
        )
        .first?
        .first?
        .doubleValue
    }

    public func saveCostOverride(carId: Int, chargeId: Int, cost: Double?) async throws {
        try Self.validate(cost)

        let database = try await databaseProvider.database()
        guard let cost else {
            try await database.run(
                "DELETE FROM charge_cost_overrides WHERE car_id = ? AND charge_id = ?;",
                bindings: [.int(carId), .int(chargeId)]
            )
            return
        }

        try await database.run(
            """
            INSERT OR REPLACE INTO charge_cost_overrides
            (charge_id, car_id, cost, updated_at)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [
                .int(chargeId),
                .int(carId),
                .double(cost),
                .text(ISO8601DateFormatter().string(from: Date()))
            ]
        )
    }

    private static func validate(_ cost: Double?) throws {
        guard let cost else {
            return
        }
        guard cost.isFinite, cost >= 0 else {
            throw ChargeCostOverrideValidationError.invalidCost
        }
    }
}
