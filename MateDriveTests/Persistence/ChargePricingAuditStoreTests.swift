import XCTest
@testable import MateDriveApp

final class ChargePricingAuditStoreTests: XCTestCase {
    func testDatabaseStoreRoundTripsReceiptAndIsolatesVehicles() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DatabaseBackedChargePricingAuditStore(databaseProvider: AuditDatabaseProvider(database: database))
        let receipt = fixtureReceipt(id: "batch-1")

        try await store.save(carId: 1, currencyCode: "CNY", receipt: receipt)
        try await store.save(carId: 2, currencyCode: "HKD", receipt: fixtureReceipt(id: "batch-2"))

        let records = try await store.records(carId: 1, limit: 20)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.id, "batch-1")
        XCTAssertEqual(record.carId, 1)
        XCTAssertEqual(record.currencyCode, "CNY")
        XCTAssertEqual(record.receipt, receipt)
    }

    func testSavingRollbackUpdatesExistingBatchWithoutDuplicatingItems() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DatabaseBackedChargePricingAuditStore(databaseProvider: AuditDatabaseProvider(database: database))
        var receipt = fixtureReceipt(id: "batch-1")
        try await store.save(carId: 1, currencyCode: "CNY", receipt: receipt)
        receipt.rollbackResults = [
            ChargePricingBatchRollbackResult(chargeId: 10, restoredCost: nil, succeeded: true, message: nil),
            ChargePricingBatchRollbackResult(chargeId: 11, restoredCost: 3, succeeded: false, message: "HTTP 500")
        ]

        try await store.save(carId: 1, currencyCode: "CNY", receipt: receipt)

        let records = try await store.records(carId: 1, limit: 20)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.receipt, receipt)
        let itemCount = try await database.intValues("SELECT COUNT(*) FROM charge_pricing_audit_items WHERE batch_id = 'batch-1';")
        XCTAssertEqual(itemCount, [2])
    }

    func testCSVExportContainsAuditEvidenceWithoutLocationOrServerCredentials() {
        let record = ChargePricingAuditRecord(carId: 1, currencyCode: "CNY", receipt: fixtureReceipt(id: "batch-1"))

        let csv = ChargePricingAuditCSVExporter.csv(records: [record])

        XCTAssertTrue(csv.contains("batch_id,created_at,currency_code,charge_id,start_date,rule_id,rule_name,previous_cost,target_cost,write_succeeded,write_message,rollback_attempted,restored_cost,rollback_succeeded,rollback_message"))
        XCTAssertTrue(csv.contains("batch-1"))
        XCTAssertTrue(csv.contains("Home, weekday"))
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("address"))
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("server_url"))
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("token"))
    }

    private func fixtureReceipt(id: String) -> ChargePricingBatchReceipt {
        ChargePricingBatchReceipt(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            results: [
                ChargePricingBatchWriteResult(
                    chargeId: 10,
                    startDate: "2026-07-01T09:00:00Z",
                    ruleID: "home",
                    ruleName: "Home, weekday",
                    previousCost: nil,
                    newCost: 5,
                    succeeded: true,
                    message: nil
                ),
                ChargePricingBatchWriteResult(
                    chargeId: 11,
                    startDate: "2026-07-02T09:00:00Z",
                    ruleID: "public",
                    ruleName: "Public DC",
                    previousCost: 3,
                    newCost: 10,
                    succeeded: false,
                    message: "HTTP 500"
                )
            ],
            rollbackResults: nil
        )
    }
}

private struct AuditDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase {
        database
    }
}
