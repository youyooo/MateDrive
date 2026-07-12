import XCTest
@testable import MateDroidIOS

final class SyncCoordinatorTests: XCTestCase {
    func testSyncSummaryPreservesMissingDriveDistanceAndDuration() async throws {
        let api = FakeSyncAPI(
            drives: [DriveData(driveId: 10, carId: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T08:30:00Z", distance: nil, durationMin: nil)],
            charges: []
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        _ = try await coordinator.syncCar(carId: 1)

        let snapshot = await stores.snapshot()
        let record = try XCTUnwrap(snapshot.driveSummaries.first)
        XCTAssertNil(record.distance)
        XCTAssertNil(record.durationMin)
    }

    func testSyncFetchesSummariesBeforeDetailsAndEnqueuesGeocode() async throws {
        let api = FakeSyncAPI(
            drives: [.fixture(id: 10, distance: 12)],
            charges: [.fixture(id: 20, energyAdded: 4)],
            driveDetails: [
                10: SyncDriveDetail(
                    driveId: 10,
                    positions: [
                        SyncDrivePosition(latitude: 48.8566, longitude: 2.3522, elevation: 10, insideTemp: 21, outsideTemp: 12, power: 20, isClimateOn: true),
                        SyncDrivePosition(latitude: 48.8666, longitude: 2.3622, elevation: 15, insideTemp: 22, outsideTemp: 14, power: -30)
                    ]
                )
            ],
            chargeDetails: [
                20: SyncChargeDetail(
                    chargeId: 20,
                    latitude: 48.8666,
                    longitude: 2.3622,
                    chargePoints: [
                        SyncChargePoint(date: "2026-01-01T09:00:00Z", chargeEnergyAdded: 0, chargerPower: 80, chargerVoltage: 400, chargerCurrent: 200, outsideTemp: 10, chargerDetails: SyncChargerDetails(fastChargerBrand: "Tesla", fastChargerType: "CCS", chargerPhases: nil)),
                        SyncChargePoint(date: "2026-01-01T09:30:00Z", chargeEnergyAdded: 4, chargerPower: 120, chargerVoltage: 400, chargerCurrent: 300, outsideTemp: 10, chargerDetails: SyncChargerDetails(fastChargerBrand: "Tesla", fastChargerType: "CCS", chargerPhases: nil))
                    ]
                )
            ]
        )
        let stores = InMemorySyncStores()
        let geocoder = FakeGeocodingService()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: geocoder)

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let snapshot = await stores.snapshot()
        XCTAssertEqual(snapshot.driveSummaries.map(\.driveId), [10])
        XCTAssertEqual(snapshot.chargeSummaries.map(\.chargeId), [20])
        XCTAssertEqual(snapshot.driveAggregates.map(\.driveId), [10])
        XCTAssertEqual(snapshot.chargeAggregates.map(\.chargeId), [20])
        let chargeAggregate = try XCTUnwrap(snapshot.chargeAggregates.first)
        let payload = try JSONDecoder().decode(TestChargeAggregatePayload.self, from: Data(chargeAggregate.payloadJSON.utf8))
        XCTAssertNil(payload.isFastCharger)
        XCTAssertEqual(payload.energySamples.map(\.date), ["2026-01-01T09:00:00Z", "2026-01-01T09:30:00Z"])
        XCTAssertEqual(payload.energySamples.map(\.chargeEnergyAdded), [0, 4])
        let enqueuedLocations = await geocoder.enqueuedSnapshot()
        let finalProgress = await coordinator.progress(for: 1)
        XCTAssertFalse(enqueuedLocations.isEmpty)
        XCTAssertEqual(finalProgress?.phase, .complete)
        XCTAssertEqual(snapshot.operations, [
            "upsertDriveSummaries",
            "upsertChargeSummaries",
            "upsertState",
            "upsertDriveAggregates",
            "upsertState",
            "upsertChargeAggregates",
            "upsertState",
            "upsertState"
        ])
    }

    func testSummaryFailureMarksSyncErrorAndStopsBeforeDetails() async throws {
        let api = FakeSyncAPI(drivesResult: .failure(.network("timeout")))
        let stores = InMemorySyncStores()
        let geocoder = FakeGeocodingService()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: geocoder)

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertFalse(success)
        let snapshot = await stores.snapshot()
        XCTAssertEqual(snapshot.driveAggregates, [])
        let progress = await coordinator.progress(for: 1)
        XCTAssertEqual(progress?.phase, .error("Failed to sync summaries"))
    }

    func testDriveDetailFailureLeavesRecordUnprocessedForRetry() async throws {
        let api = FakeSyncAPI(
            drives: [
                .fixture(id: 10, distance: 12),
                .fixture(id: 11, distance: 18)
            ],
            charges: [],
            driveDetails: [
                10: SyncDriveDetail(driveId: 10, positions: [
                    SyncDrivePosition(latitude: 48.8566, longitude: 2.3522)
                ])
            ]
        )
        let stores = InMemorySyncStores()
        let geocoder = FakeGeocodingService()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: geocoder)

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertFalse(success)
        let snapshot = await stores.snapshot()
        let unprocessedDriveIds = try await stores.unprocessedDriveIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertEqual(snapshot.driveAggregates.map(\.driveId), [10])
        XCTAssertEqual(unprocessedDriveIds, [11])
        XCTAssertEqual(snapshot.state?.drivesProcessed, 1)
        XCTAssertEqual(snapshot.state?.lastDriveDetailId, 10)
        XCTAssertEqual(snapshot.state?.detailsSynced, false)
        let progress = await coordinator.progress(for: 1)
        XCTAssertEqual(progress?.phase, .error("Failed to sync drive details"))
    }

    func testChargeDetailFailureLeavesRecordUnprocessedForRetry() async throws {
        let api = FakeSyncAPI(
            drives: [],
            charges: [
                .fixture(id: 20, energyAdded: 4),
                .fixture(id: 21, energyAdded: 6)
            ],
            chargeDetails: [
                20: SyncChargeDetail(
                    chargeId: 20,
                    latitude: 48.8666,
                    longitude: 2.3622,
                    chargePoints: [
                        SyncChargePoint(date: "2026-01-01T09:00:00Z", chargeEnergyAdded: 0),
                        SyncChargePoint(date: "2026-01-01T09:30:00Z", chargeEnergyAdded: 4)
                    ]
                )
            ]
        )
        let stores = InMemorySyncStores()
        let geocoder = FakeGeocodingService()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: geocoder)

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertFalse(success)
        let snapshot = await stores.snapshot()
        let unprocessedChargeIds = try await stores.unprocessedChargeIds(carId: 1, schemaVersion: SchemaVersion.current)
        XCTAssertEqual(snapshot.chargeAggregates.map(\.chargeId), [20])
        XCTAssertEqual(unprocessedChargeIds, [21])
        XCTAssertEqual(snapshot.state?.chargesProcessed, 1)
        XCTAssertEqual(snapshot.state?.lastChargeDetailId, 20)
        XCTAssertEqual(snapshot.state?.detailsSynced, false)
        let progress = await coordinator.progress(for: 1)
        XCTAssertEqual(progress?.phase, .error("Failed to sync charge details"))
    }

    func testChargeAggregateMarksZeroPhaseAsFastCharger() async throws {
        let api = FakeSyncAPI(
            drives: [],
            charges: [.fixture(id: 22, energyAdded: 20)],
            chargeDetails: [
                22: SyncChargeDetail(
                    chargeId: 22,
                    chargePoints: [
                        SyncChargePoint(date: "2026-01-01T09:00:00Z", chargeEnergyAdded: 0, chargerDetails: SyncChargerDetails(chargerPhases: 0)),
                        SyncChargePoint(date: "2026-01-01T09:30:00Z", chargeEnergyAdded: 20, chargerDetails: SyncChargerDetails(chargerPhases: 0))
                    ]
                )
            ]
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let snapshot = await stores.snapshot()
        let aggregate = try XCTUnwrap(snapshot.chargeAggregates.first)
        let payload = try JSONDecoder().decode(TestChargeAggregatePayload.self, from: Data(aggregate.payloadJSON.utf8))
        XCTAssertEqual(payload.isFastCharger, true)
    }

    func testChargeAggregateMarksPositivePhaseAsNotFastCharger() async throws {
        let api = FakeSyncAPI(
            drives: [],
            charges: [.fixture(id: 23, energyAdded: 7)],
            chargeDetails: [
                23: SyncChargeDetail(
                    chargeId: 23,
                    chargePoints: [
                        SyncChargePoint(date: "2026-01-01T09:00:00Z", chargeEnergyAdded: 0, chargerDetails: SyncChargerDetails(chargerPhases: 3)),
                        SyncChargePoint(date: "2026-01-01T11:00:00Z", chargeEnergyAdded: 7, chargerDetails: SyncChargerDetails(chargerPhases: 3))
                    ]
                )
            ]
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let snapshot = await stores.snapshot()
        let aggregate = try XCTUnwrap(snapshot.chargeAggregates.first)
        let payload = try JSONDecoder().decode(TestChargeAggregatePayload.self, from: Data(aggregate.payloadJSON.utf8))
        XCTAssertEqual(payload.isFastCharger, false)
    }

    func testChargeAggregatePrefersExplicitFastChargerFlagOverPhaseHeuristic() async throws {
        let api = FakeSyncAPI(
            driveDetails: [:],
            chargeDetails: [
                30: SyncChargeDetail(
                    chargeId: 30,
                    chargePoints: [
                        SyncChargePoint(
                            date: "2026-01-01T09:00:00Z",
                            chargeEnergyAdded: 0,
                            chargerDetails: SyncChargerDetails(fastChargerPresent: true, chargerPhases: 3)
                        ),
                        SyncChargePoint(
                            date: "2026-01-01T09:30:00Z",
                            chargeEnergyAdded: 20,
                            chargerDetails: SyncChargerDetails(fastChargerPresent: true, chargerPhases: 3)
                        )
                    ]
                )
            ],
            drivesResult: .success([]),
            chargesResult: .success([.fixture(id: 30, energyAdded: 20)])
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)
        let snapshot = await stores.snapshot()
        XCTAssertTrue(success)
        let payload = try XCTUnwrap(snapshot.chargeAggregates.first?.payloadJSON.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])

        XCTAssertEqual(json["isFastCharger"] as? Bool, true)
    }
}

private struct TestChargeAggregatePayload: Decodable {
    let isFastCharger: Bool?
    let energySamples: [TestChargeEnergySample]
}

private struct TestChargeEnergySample: Decodable {
    let date: String?
    let chargeEnergyAdded: Double?
}

private final class FakeSyncAPI: SyncAPIProviding, @unchecked Sendable {
    private let drivesResult: APIResult<[DriveData]>
    private let chargesResult: APIResult<[ChargeData]>
    private let driveDetails: [Int: SyncDriveDetail]
    private let chargeDetails: [Int: SyncChargeDetail]

    init(
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        driveDetails: [Int: SyncDriveDetail] = [:],
        chargeDetails: [Int: SyncChargeDetail] = [:],
        drivesResult: APIResult<[DriveData]>? = nil,
        chargesResult: APIResult<[ChargeData]>? = nil
    ) {
        self.drivesResult = drivesResult ?? .success(drives)
        self.chargesResult = chargesResult ?? .success(charges)
        self.driveDetails = driveDetails
        self.chargeDetails = chargeDetails
    }

    func drives(carId _: Int) async -> APIResult<[DriveData]> {
        drivesResult
    }

    func charges(carId _: Int) async -> APIResult<[ChargeData]> {
        chargesResult
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<SyncDriveDetail> {
        driveDetails[driveId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId: Int) async -> APIResult<SyncChargeDetail> {
        chargeDetails[chargeId].map(APIResult.success) ?? .failure(.emptyBody)
    }
}

private actor FakeGeocodingService: SyncGeocodingServicing {
    private(set) var enqueuedLocations: [GeocodeLocation] = []

    func enqueueLocations(carId _: Int, locations: [GeocodeLocation]) async throws -> Int {
        enqueuedLocations.append(contentsOf: locations)
        return locations.count
    }

    func enqueuedSnapshot() -> [GeocodeLocation] {
        enqueuedLocations
    }
}

private actor InMemorySyncStores: SyncPersisting {
    private var driveSummaries: [DriveSummaryRecord] = []
    private var chargeSummaries: [ChargeSummaryRecord] = []
    private var driveAggregates: [DriveDetailAggregateRecord] = []
    private var chargeAggregates: [ChargeDetailAggregateRecord] = []
    private var states: [Int: SyncStateRecord] = [:]
    private var operations: [String] = []

    func snapshot() -> Snapshot {
        Snapshot(
            driveSummaries: driveSummaries,
            chargeSummaries: chargeSummaries,
            driveAggregates: driveAggregates,
            chargeAggregates: chargeAggregates,
            state: states[1],
            operations: operations
        )
    }

    func upsertDriveSummaries(_ records: [DriveSummaryRecord]) async throws {
        driveSummaries = records
        operations.append("upsertDriveSummaries")
    }

    func upsertChargeSummaries(_ records: [ChargeSummaryRecord]) async throws {
        chargeSummaries = records
        operations.append("upsertChargeSummaries")
    }

    func unprocessedDriveIds(carId: Int, schemaVersion: Int) async throws -> [Int] {
        driveSummaries.filter { $0.carId == carId && $0.schemaVersion != schemaVersion }.map(\.driveId)
    }

    func unprocessedChargeIds(carId: Int, schemaVersion: Int) async throws -> [Int] {
        chargeSummaries.filter { $0.carId == carId && $0.schemaVersion != schemaVersion }.map(\.chargeId)
    }

    func upsertDriveAggregates(_ records: [DriveDetailAggregateRecord]) async throws {
        driveAggregates.append(contentsOf: records)
        driveSummaries = driveSummaries.map { record in
            records.contains { $0.driveId == record.driveId }
                ? DriveSummaryRecord(driveId: record.driveId, carId: record.carId, startDate: record.startDate, endDate: record.endDate, distance: record.distance, durationMin: record.durationMin, schemaVersion: SchemaVersion.current)
                : record
        }
        operations.append("upsertDriveAggregates")
    }

    func upsertChargeAggregates(_ records: [ChargeDetailAggregateRecord]) async throws {
        chargeAggregates.append(contentsOf: records)
        chargeSummaries = chargeSummaries.map { record in
            records.contains { $0.chargeId == record.chargeId }
                ? ChargeSummaryRecord(chargeId: record.chargeId, carId: record.carId, startDate: record.startDate, endDate: record.endDate, chargeEnergyAdded: record.chargeEnergyAdded, cost: record.cost, schemaVersion: SchemaVersion.current)
                : record
        }
        operations.append("upsertChargeAggregates")
    }

    func state(carId: Int) async throws -> SyncStateRecord? {
        states[carId]
    }

    func upsertState(_ state: SyncStateRecord) async throws {
        states[state.carId] = state
        operations.append("upsertState")
    }

    struct Snapshot: Equatable {
        let driveSummaries: [DriveSummaryRecord]
        let chargeSummaries: [ChargeSummaryRecord]
        let driveAggregates: [DriveDetailAggregateRecord]
        let chargeAggregates: [ChargeDetailAggregateRecord]
        let state: SyncStateRecord?
        let operations: [String]
    }
}

private extension DriveData {
    static func fixture(id: Int, distance: Double) -> DriveData {
        DriveData(
            driveId: id,
            carId: 1,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T08:30:00Z",
            distance: distance,
            durationMin: 30,
            startAddress: nil,
            endAddress: nil,
            averageSpeed: nil,
            powerMax: nil
        )
    }
}

private extension ChargeData {
    static func fixture(id: Int, energyAdded: Double) -> ChargeData {
        ChargeData(
            chargeId: id,
            carId: 1,
            startDate: "2026-01-01T09:00:00Z",
            endDate: "2026-01-01T09:30:00Z",
            chargeEnergyAdded: energyAdded,
            cost: nil,
            chargerPower: nil,
            chargerPhases: nil,
            startBatteryLevel: nil,
            endBatteryLevel: nil
        )
    }
}
