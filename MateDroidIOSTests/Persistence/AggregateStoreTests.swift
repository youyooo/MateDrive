import XCTest
@testable import MateDroidIOS

final class AggregateStoreTests: XCTestCase {
    func testDriveSummaryStorePersistsEnergyAndReadsVehicleScopedRows() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DriveSummaryStore(database: database)

        try await store.upsertAll([
            DriveSummaryRecord(driveId: 10, carId: 1, startDate: "start", endDate: "end", distance: 20, durationMin: 30, energyConsumedNet: 4.2, consumptionNet: 210),
            DriveSummaryRecord(driveId: 11, carId: 2, startDate: "other", endDate: "other-end", distance: 1, durationMin: 2, energyConsumedNet: 0.2, consumptionNet: 200)
        ])

        let records = try await store.records(carId: 1)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.driveId, 10)
        XCTAssertEqual(records.first?.energyConsumedNet, 4.2)
        XCTAssertEqual(records.first?.consumptionNet, 210)
    }

    func testDatabaseBackedSyncStorePreservesProcessedVersionWhenSummariesRefresh() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DatabaseBackedSyncStore(databaseProvider: SyncStaticDatabaseProvider(database: database))
        let drive = DriveSummaryRecord(driveId: 10, carId: 1, startDate: "2026-07-01T08:00:00Z", endDate: "2026-07-01T08:30:00Z", distance: 20, durationMin: 30, schemaVersion: 0)
        let charge = ChargeSummaryRecord(chargeId: 20, carId: 1, startDate: "2026-07-01T09:00:00Z", endDate: "2026-07-01T10:00:00Z", chargeEnergyAdded: 10, cost: nil, schemaVersion: 0)

        try await store.upsertDriveSummaries([drive])
        try await store.upsertChargeSummaries([charge])
        let initialDriveIDs = try await store.unprocessedDriveIds(carId: 1, schemaVersion: SchemaVersion.current)
        let initialChargeIDs = try await store.unprocessedChargeIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertEqual(initialDriveIDs, [10])
        XCTAssertEqual(initialChargeIDs, [20])
        let healthProvider = DatabaseBackedHistorySyncHealthProvider(databaseProvider: SyncStaticDatabaseProvider(database: database))
        let pendingHealth = try await healthProvider.health(carId: 1)
        XCTAssertEqual(pendingHealth.driveSummaryCount, 1)
        XCTAssertEqual(pendingHealth.driveDetailCount, 0)
        XCTAssertEqual(pendingHealth.pendingDriveCount, 1)
        XCTAssertEqual(pendingHealth.pendingChargeCount, 1)
        XCTAssertFalse(pendingHealth.isComplete)

        try await store.upsertDriveAggregates([DriveDetailAggregateRecord(driveId: 10, carId: 1, payloadJSON: "{}", schemaVersion: SchemaVersion.current)])
        try await store.upsertChargeAggregates([ChargeDetailAggregateRecord(chargeId: 20, carId: 1, payloadJSON: "{}", schemaVersion: SchemaVersion.current)])
        try await store.upsertDriveSummaries([drive])
        try await store.upsertChargeSummaries([charge])
        try await store.upsertState(SyncStateRecord(carId: 1, lastDriveSyncAt: 1_000, lastChargeSyncAt: 2_000, summariesSynced: true, detailsSynced: true))

        let refreshedDriveIDs = try await store.unprocessedDriveIds(carId: 1, schemaVersion: SchemaVersion.current)
        let refreshedChargeIDs = try await store.unprocessedChargeIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertTrue(refreshedDriveIDs.isEmpty)
        XCTAssertTrue(refreshedChargeIDs.isEmpty)
        let completeHealth = try await healthProvider.health(carId: 1)
        XCTAssertEqual(completeHealth.driveDetailCount, 1)
        XCTAssertEqual(completeHealth.chargeDetailCount, 1)
        XCTAssertEqual(completeHealth.lastSyncAtMilliseconds, 2_000)
        XCTAssertTrue(completeHealth.isComplete)
    }

    func testChargePricingAggregatesRestoreEnergySamplesAndDcClassification() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = AggregateStore(database: database)
        let payload = """
        {
          "isFastCharger": true,
          "fastChargerBrand": "Tesla",
          "chargerPhases": 0,
          "energySamples": [
            {"date": "2026-07-01T09:00:00Z", "chargeEnergyAdded": 0},
            {"date": "2026-07-01T09:30:00Z", "chargeEnergyAdded": 12.5}
          ]
        }
        """
        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(
                chargeId: 20,
                carId: 1,
                payloadJSON: payload,
                schemaVersion: SchemaVersion.current
            )
        )

        let aggregates = try await store.chargePricingAggregates(carId: 1)

        let aggregate = try XCTUnwrap(aggregates[20])
        XCTAssertEqual(aggregate.isDc, true)
        XCTAssertEqual(aggregate.chargerIdentity, .teslaSupercharger)
        XCTAssertEqual(aggregate.energySamples, [
            ChargePricingEnergySample(date: "2026-07-01T09:00:00Z", cumulativeEnergyAddedKWh: 0),
            ChargePricingEnergySample(date: "2026-07-01T09:30:00Z", cumulativeEnergyAddedKWh: 12.5)
        ])
    }

    func testChargePricingAggregatesIgnoreOtherCarsOldSchemasAndMalformedPayloads() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = AggregateStore(database: database)
        let validPayload = #"{"isFastCharger":false,"energySamples":[]}"#

        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(chargeId: 1, carId: 1, payloadJSON: validPayload, schemaVersion: SchemaVersion.current)
        )
        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(chargeId: 2, carId: 2, payloadJSON: validPayload, schemaVersion: SchemaVersion.current)
        )
        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(chargeId: 3, carId: 1, payloadJSON: validPayload, schemaVersion: SchemaVersion.current - 1)
        )
        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(chargeId: 4, carId: 1, payloadJSON: "not-json", schemaVersion: SchemaVersion.current)
        )

        let aggregates = try await store.chargePricingAggregates(carId: 1)

        XCTAssertEqual(Array(aggregates.keys), [1])
        XCTAssertEqual(aggregates[1]?.isDc, false)
        XCTAssertEqual(aggregates[1]?.chargerIdentity, .ac)
    }

    func testChargePricingAggregatesDistinguishThirdPartyAndUnknownDcChargers() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = AggregateStore(database: database)

        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(
                chargeId: 30,
                carId: 1,
                payloadJSON: #"{"isFastCharger":true,"fastChargerBrand":"ChargePoint","chargerPhases":0}"#,
                schemaVersion: SchemaVersion.current
            )
        )
        try await store.upsertChargeAggregate(
            ChargeDetailAggregateRecord(
                chargeId: 31,
                carId: 1,
                payloadJSON: #"{"isFastCharger":true,"fastChargerBrand":"<invalid>","chargerPhases":0}"#,
                schemaVersion: SchemaVersion.current
            )
        )

        let aggregates = try await store.chargePricingAggregates(carId: 1)

        XCTAssertEqual(aggregates[30]?.chargerIdentity, .otherDC)
        XCTAssertEqual(aggregates[31]?.chargerIdentity, .unknownDC)
    }
}

private struct SyncStaticDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase { database }
}
