import Foundation

public protocol ChargePricingAuditStoring: Sendable {
    func save(carId: Int, currencyCode: String, receipt: ChargePricingBatchReceipt) async throws
    func records(carId: Int, limit: Int) async throws -> [ChargePricingAuditRecord]
}

public struct EmptyChargePricingAuditStore: ChargePricingAuditStoring {
    public init() {}

    public func save(carId _: Int, currencyCode _: String, receipt _: ChargePricingBatchReceipt) async throws {}

    public func records(carId _: Int, limit _: Int) async throws -> [ChargePricingAuditRecord] {
        []
    }
}

public struct DatabaseBackedChargePricingAuditStore: ChargePricingAuditStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func save(carId: Int, currencyCode: String, receipt: ChargePricingBatchReceipt) async throws {
        let database = try await databaseProvider.database()
        let timestamp = Self.dateString(receipt.createdAt)
        let rollbackByChargeID = Dictionary(uniqueKeysWithValues: (receipt.rollbackResults ?? []).map { ($0.chargeId, $0) })
        var commands = [
            SQLiteCommand(
                """
                INSERT OR REPLACE INTO charge_pricing_audit_batches
                (batch_id, car_id, created_at, currency_code, updated_at)
                VALUES (?, ?, ?, ?, ?);
                """,
                bindings: [.text(receipt.id), .int(carId), .text(timestamp), .text(currencyCode), .text(Self.dateString(Date()))]
            ),
            SQLiteCommand(
                "DELETE FROM charge_pricing_audit_items WHERE batch_id = ?;",
                bindings: [.text(receipt.id)]
            )
        ]

        for (index, result) in receipt.results.enumerated() {
            let rollback = rollbackByChargeID[result.chargeId]
            commands.append(SQLiteCommand(
                """
                INSERT INTO charge_pricing_audit_items
                (batch_id, sequence, charge_id, start_date, rule_id, rule_name,
                 previous_cost, target_cost, write_succeeded, write_message,
                 rollback_attempted, restored_cost, rollback_succeeded, rollback_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(receipt.id),
                    .int(index),
                    .int(result.chargeId),
                    .text(result.startDate),
                    .text(result.ruleID),
                    .text(result.ruleName),
                    Self.sqliteValue(result.previousCost),
                    .double(result.newCost),
                    .int(result.succeeded ? 1 : 0),
                    Self.sqliteValue(result.message),
                    .int(rollback == nil ? 0 : 1),
                    Self.sqliteValue(rollback?.restoredCost),
                    rollback.map { .int($0.succeeded ? 1 : 0) } ?? .null,
                    Self.sqliteValue(rollback?.message)
                ]
            ))
        }
        try await database.performTransaction(commands)
    }

    public func records(carId: Int, limit: Int) async throws -> [ChargePricingAuditRecord] {
        let database = try await databaseProvider.database()
        let safeLimit = max(0, min(limit, 500))
        let batchRows = try await database.rows(
            """
            SELECT batch_id, created_at, currency_code
            FROM charge_pricing_audit_batches
            WHERE car_id = ?
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            bindings: [.int(carId), .int(safeLimit)]
        )

        var records: [ChargePricingAuditRecord] = []
        for row in batchRows {
            guard row.count >= 3,
                  let batchID = row[0].textValue,
                  let createdAtValue = row[1].textValue,
                  let createdAt = Self.date(createdAtValue),
                  let currencyCode = row[2].textValue
            else { continue }
            let itemRows = try await database.rows(
                """
                SELECT charge_id, start_date, rule_id, rule_name, previous_cost,
                       target_cost, write_succeeded, write_message, rollback_attempted,
                       restored_cost, rollback_succeeded, rollback_message
                FROM charge_pricing_audit_items
                WHERE batch_id = ?
                ORDER BY sequence ASC;
                """,
                bindings: [.text(batchID)]
            )
            let results = itemRows.compactMap(Self.writeResult)
            guard !results.isEmpty else { continue }
            let rollbackResults = itemRows.compactMap(Self.rollbackResult)
            let receipt = ChargePricingBatchReceipt(
                id: batchID,
                createdAt: createdAt,
                results: results,
                rollbackResults: rollbackResults.isEmpty ? nil : rollbackResults
            )
            records.append(ChargePricingAuditRecord(carId: carId, currencyCode: currencyCode, receipt: receipt))
        }
        return records
    }

    private static func writeResult(_ row: [SQLiteColumnValue]) -> ChargePricingBatchWriteResult? {
        guard row.count >= 12,
              let chargeID = row[0].intValue,
              let startDate = row[1].textValue,
              let ruleID = row[2].textValue,
              let ruleName = row[3].textValue,
              let targetCost = row[5].doubleValue,
              let succeeded = row[6].intValue
        else { return nil }
        return ChargePricingBatchWriteResult(
            chargeId: chargeID,
            startDate: startDate,
            ruleID: ruleID,
            ruleName: ruleName,
            previousCost: row[4].doubleValue,
            newCost: targetCost,
            succeeded: succeeded != 0,
            message: row[7].textValue
        )
    }

    private static func rollbackResult(_ row: [SQLiteColumnValue]) -> ChargePricingBatchRollbackResult? {
        guard row.count >= 12,
              row[8].intValue == 1,
              let chargeID = row[0].intValue,
              let succeeded = row[10].intValue
        else { return nil }
        return ChargePricingBatchRollbackResult(
            chargeId: chargeID,
            restoredCost: row[9].doubleValue,
            succeeded: succeeded != 0,
            message: row[11].textValue
        )
    }

    private static func sqliteValue(_ value: Double?) -> SQLiteValue {
        value.map(SQLiteValue.double) ?? .null
    }

    private static func sqliteValue(_ value: String?) -> SQLiteValue {
        value.map(SQLiteValue.text) ?? .null
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

public enum ChargePricingAuditCSVExporter {
    public static func csv(records: [ChargePricingAuditRecord]) -> String {
        let header = [
            "batch_id", "created_at", "currency_code", "charge_id", "start_date",
            "rule_id", "rule_name", "previous_cost", "target_cost", "write_succeeded",
            "write_message", "rollback_attempted", "restored_cost", "rollback_succeeded",
            "rollback_message"
        ].joined(separator: ",")
        let rows = records.flatMap { record in
            let rollbackByChargeID = Dictionary(uniqueKeysWithValues: (record.receipt.rollbackResults ?? []).map { ($0.chargeId, $0) })
            return record.receipt.results.map { result in
                let rollback = rollbackByChargeID[result.chargeId]
                return [
                    record.id,
                    ISO8601DateFormatter().string(from: record.receipt.createdAt),
                    record.currencyCode,
                    String(result.chargeId),
                    result.startDate,
                    result.ruleID,
                    result.ruleName,
                    number(result.previousCost),
                    number(result.newCost),
                    result.succeeded ? "true" : "false",
                    result.message ?? "",
                    rollback == nil ? "false" : "true",
                    number(rollback?.restoredCost),
                    rollback.map { $0.succeeded ? "true" : "false" } ?? "",
                    rollback?.message ?? ""
                ].map(escape).joined(separator: ",")
            }
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.6f", $0) } ?? ""
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
