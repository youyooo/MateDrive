import XCTest
@testable import MateDriveApp

final class AggregateStoreTests: XCTestCase {
    func testChargeSummaryStorePersistsPresentationFieldsForOfflineRows() async throws {
        let fixtureLatitude = 12.3456
        let fixtureLongitude = 34.5678
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = ChargeSummaryStore(database: database)

        try await store.upsertAll([
            ChargeSummaryRecord(
                chargeId: 20,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: "2026-07-01T10:00:00Z",
                chargeEnergyAdded: 12.5,
                cost: 8.25,
                durationMin: 60,
                address: "Example Charge Site",
                latitude: fixtureLatitude,
                longitude: fixtureLongitude,
                chargeEnergyUsed: 14.1,
                startBatteryLevel: 20,
                endBatteryLevel: 80,
                startRatedRangeKm: 90,
                endRatedRangeKm: 360,
                odometerKm: 118_000
            ),
            ChargeSummaryRecord(
                chargeId: 21,
                carId: 2,
                startDate: "2026-07-02T09:00:00Z",
                endDate: nil,
                chargeEnergyAdded: nil,
                cost: nil
            )
        ])

        let records = try await store.records(carId: 1)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.chargeId, 20)
        XCTAssertEqual(records.first?.durationMin, 60)
        XCTAssertEqual(records.first?.address, "Example Charge Site")
        XCTAssertEqual(records.first?.latitude, fixtureLatitude)
        XCTAssertEqual(records.first?.longitude, fixtureLongitude)
        XCTAssertEqual(records.first?.chargeEnergyUsed, 14.1)
        XCTAssertEqual(records.first?.startBatteryLevel, 20)
        XCTAssertEqual(records.first?.endBatteryLevel, 80)
        XCTAssertEqual(records.first?.endRatedRangeKm, 360)
        XCTAssertEqual(records.first?.odometerKm, 118_000)
    }

    func testSparseChargeSummaryRefreshPreservesKnownTelemetryAndClearsRemovedServerCost() async throws {
        let coordinate = SyntheticCoordinates.point()
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = ChargeSummaryStore(database: database)
        try await store.upsertAll([
            ChargeSummaryRecord(
                chargeId: 20,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: "2026-07-01T10:00:00Z",
                chargeEnergyAdded: 12.5,
                cost: 8.25,
                durationMin: 60,
                address: "Example Charge Site",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        ])

        try await store.upsertAll([
            ChargeSummaryRecord(
                chargeId: 20,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: nil,
                chargeEnergyAdded: nil,
                cost: nil
            )
        ])

        let records = try await store.records(carId: 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.endDate, "2026-07-01T10:00:00Z")
        XCTAssertEqual(record.chargeEnergyAdded, 12.5)
        XCTAssertEqual(record.durationMin, 60)
        XCTAssertEqual(record.address, "Example Charge Site")
        XCTAssertEqual(record.latitude, coordinate.latitude)
        XCTAssertEqual(record.longitude, coordinate.longitude)
        XCTAssertNil(record.cost)
    }

    func testDriveSummaryStorePersistsEnergyAndReadsVehicleScopedRows() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DriveSummaryStore(database: database)

        try await store.upsertAll([
            DriveSummaryRecord(
                driveId: 10,
                carId: 1,
                startDate: "start",
                endDate: "end",
                distance: 20,
                durationMin: 30,
                energyConsumedNet: 4.2,
                consumptionNet: 210,
                startBatteryLevel: 80,
                endBatteryLevel: 70,
                startRatedRangeKm: 410,
                endRatedRangeKm: 372
            ),
            DriveSummaryRecord(driveId: 11, carId: 2, startDate: "other", endDate: "other-end", distance: 1, durationMin: 2, energyConsumedNet: 0.2, consumptionNet: 200)
        ])

        let records = try await store.records(carId: 1)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.driveId, 10)
        XCTAssertEqual(records.first?.energyConsumedNet, 4.2)
        XCTAssertEqual(records.first?.consumptionNet, 210)
        XCTAssertEqual(records.first?.startBatteryLevel, 80)
        XCTAssertEqual(records.first?.endBatteryLevel, 70)
        XCTAssertEqual(records.first?.startRatedRangeKm, 410)
        XCTAssertEqual(records.first?.endRatedRangeKm, 372)
    }

    func testSparseDriveSummaryRefreshPreservesKnownDistanceAndDuration() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DriveSummaryStore(database: database)
        try await store.upsertAll([
            DriveSummaryRecord(
                driveId: 10,
                carId: 1,
                startDate: "start",
                endDate: "end",
                distance: 20,
                durationMin: 30
            )
        ])

        try await store.upsertAll([
            DriveSummaryRecord(
                driveId: 10,
                carId: 1,
                startDate: "start",
                endDate: "end",
                distance: nil,
                durationMin: nil
            )
        ])

        let records = try await store.records(carId: 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.distance, 20)
        XCTAssertEqual(record.durationMin, 30)
    }

    func testDriveSummaryRefreshDoesNotErasePreviouslyReconstructedEnergy() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DriveSummaryStore(database: database)
        let enriched = DriveSummaryRecord(
            driveId: 10,
            carId: 1,
            startDate: "start",
            endDate: "end",
            distance: 20,
            durationMin: 30,
            energyConsumedNet: 4.2,
            consumptionNet: 210,
            energySource: DriveEnergySource.powerSamples.rawValue
        )
        let summaryRefresh = DriveSummaryRecord(
            driveId: 10,
            carId: 1,
            startDate: "start-new",
            endDate: "end-new",
            distance: 20,
            durationMin: 30,
            energyConsumedNet: nil,
            consumptionNet: nil,
            energySource: nil,
            schemaVersion: 0
        )

        try await store.upsertAll([enriched])
        try await store.upsertAll([summaryRefresh])

        let records = try await store.records(carId: 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.energyConsumedNet, 4.2)
        XCTAssertEqual(record.consumptionNet, 210)
        XCTAssertEqual(record.energySource, DriveEnergySource.powerSamples.rawValue)
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

    func testUnprocessedDetailsPrioritizeNewestRecordsForBackgroundHydration() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let driveStore = DriveSummaryStore(database: database)
        let chargeStore = ChargeSummaryStore(database: database)

        try await driveStore.upsertAll([
            DriveSummaryRecord(
                driveId: 10,
                carId: 1,
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T08:30:00Z",
                distance: nil,
                durationMin: nil,
                schemaVersion: 0
            ),
            DriveSummaryRecord(
                driveId: 12,
                carId: 1,
                startDate: "2026-07-03T08:00:00Z",
                endDate: "2026-07-03T08:30:00Z",
                distance: nil,
                durationMin: nil,
                schemaVersion: 0
            ),
            DriveSummaryRecord(
                driveId: 11,
                carId: 1,
                startDate: "2026-07-02T08:00:00Z",
                endDate: "2026-07-02T08:30:00Z",
                distance: nil,
                durationMin: nil,
                schemaVersion: 0
            )
        ])
        try await chargeStore.upsertAll([
            ChargeSummaryRecord(
                chargeId: 20,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: nil,
                chargeEnergyAdded: nil,
                cost: nil,
                schemaVersion: 0
            ),
            ChargeSummaryRecord(
                chargeId: 22,
                carId: 1,
                startDate: "2026-07-03T09:00:00Z",
                endDate: nil,
                chargeEnergyAdded: nil,
                cost: nil,
                schemaVersion: 0
            ),
            ChargeSummaryRecord(
                chargeId: 21,
                carId: 1,
                startDate: "2026-07-02T09:00:00Z",
                endDate: nil,
                chargeEnergyAdded: nil,
                cost: nil,
                schemaVersion: 0
            )
        ])

        let driveIDs = try await driveStore.unprocessedDriveIds(
            carId: 1,
            schemaVersion: SchemaVersion.current
        )
        let chargeIDs = try await chargeStore.unprocessedChargeIds(
            carId: 1,
            schemaVersion: SchemaVersion.current
        )

        XCTAssertEqual(driveIDs, [12, 11, 10])
        XCTAssertEqual(chargeIDs, [22, 21, 20])
    }

    func testDatabaseBackedSyncStoreWritesDetailEnergyIntoDriveSummary() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = DatabaseBackedSyncStore(databaseProvider: SyncStaticDatabaseProvider(database: database))
        try await store.upsertDriveSummaries([
            DriveSummaryRecord(
                driveId: 10,
                carId: 1,
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T08:30:00Z",
                distance: 20,
                durationMin: 30,
                schemaVersion: 0
            )
        ])

        try await store.upsertDriveAggregates([
            DriveDetailAggregateRecord(
                driveId: 10,
                carId: 1,
                payloadJSON: "{}",
                schemaVersion: SchemaVersion.current,
                energyConsumedNet: 4.2,
                consumptionNet: 210,
                energySource: DriveEnergySource.powerSamples.rawValue
            )
        ])

        let records = try await DriveSummaryStore(database: database).records(carId: 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.energyConsumedNet, 4.2)
        XCTAssertEqual(record.consumptionNet, 210)
        XCTAssertEqual(record.energySource, DriveEnergySource.powerSamples.rawValue)
        let unprocessed = try await store.unprocessedDriveIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertTrue(unprocessed.isEmpty)
    }

    func testDatabaseBackedSyncStoreWritesChargeDetailTelemetryIntoSummary() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let provider = SyncStaticDatabaseProvider(database: database)
        let store = DatabaseBackedSyncStore(databaseProvider: provider)
        try await store.upsertChargeSummaries([
            ChargeSummaryRecord(
                chargeId: 20,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: "2026-07-01T10:00:00Z",
                chargeEnergyAdded: nil,
                cost: nil,
                schemaVersion: 0
            )
        ])

        try await store.upsertChargeAggregates([
            ChargeDetailAggregateRecord(
                chargeId: 20,
                carId: 1,
                payloadJSON: "{}",
                schemaVersion: SchemaVersion.current,
                chargeEnergyAdded: 40,
                chargeEnergyUsed: 44,
                startBatteryLevel: 20,
                endBatteryLevel: 80,
                startRatedRangeKm: 90,
                endRatedRangeKm: 360,
                odometerKm: 118_000
            )
        ])

        let records = try await ChargeSummaryStore(database: database).records(carId: 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.chargeEnergyAdded, 40)
        XCTAssertEqual(record.chargeEnergyUsed, 44)
        XCTAssertEqual(record.startBatteryLevel, 20)
        XCTAssertEqual(record.endBatteryLevel, 80)
        XCTAssertEqual(record.endRatedRangeKm, 360)
        XCTAssertEqual(record.odometerKm, 118_000)
        let unprocessed = try await store.unprocessedChargeIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertTrue(unprocessed.isEmpty)
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
