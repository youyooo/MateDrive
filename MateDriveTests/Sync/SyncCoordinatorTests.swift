import XCTest
@testable import MateDriveApp

final class SyncCoordinatorTests: XCTestCase {
    func testSummarySyncPaginatesUntilServerEnd() async throws {
        let drives = (1...201).map { DriveData.fixture(id: $0, distance: Double($0)) }
        let details = Dictionary(uniqueKeysWithValues: drives.compactMap { drive -> (Int, SyncDriveDetail)? in
            guard let id = drive.driveId else { return nil }
            return (id, SyncDriveDetail(driveId: id, positions: []))
        })
        let api = FakeSyncAPI(drives: drives, driveDetails: details)
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let snapshot = await stores.snapshot()
        XCTAssertEqual(snapshot.driveSummaries.count, 201)
        XCTAssertEqual(api.drivePageRequests, [1, 2, 3])
        XCTAssertEqual(
            api.drivePageSizes,
            [SyncCoordinator.summaryPageSize, SyncCoordinator.summaryPageSize, SyncCoordinator.summaryPageSize]
        )
        XCTAssertEqual(api.chargePageRequests, [1])
    }

    func testSummarySyncContinuesWhenServerCapsPagesBelowRequestedSize() async throws {
        let drives = (1...153).map { DriveData.fixture(id: $0, distance: Double($0)) }
        let charges = (1...37).map { ChargeData.fixture(id: $0, energyAdded: Double($0)) }
        let driveDetails = Dictionary(uniqueKeysWithValues: drives.compactMap { drive -> (Int, SyncDriveDetail)? in
            guard let id = drive.driveId else { return nil }
            return (id, SyncDriveDetail(driveId: id, positions: []))
        })
        let chargeDetails = Dictionary(uniqueKeysWithValues: charges.compactMap { charge -> (Int, SyncChargeDetail)? in
            guard let id = charge.chargeId else { return nil }
            return (id, SyncChargeDetail(chargeId: id, chargePoints: []))
        })
        let api = FakeSyncAPI(
            drives: drives,
            charges: charges,
            driveDetails: driveDetails,
            chargeDetails: chargeDetails,
            maximumPageSize: 100
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let snapshot = await stores.snapshot()
        XCTAssertEqual(snapshot.driveSummaries.count, 153)
        XCTAssertEqual(snapshot.chargeSummaries.count, 37)
        XCTAssertEqual(api.drivePageRequests, [1, 2, 3])
        XCTAssertEqual(api.chargePageRequests, [1, 2])
    }

    func testRepeatedFullSummaryPageFailsWithoutMarkingHistoryComplete() async throws {
        let repeated = (1...SyncCoordinator.summaryPageSize).map {
            DriveData.fixture(id: $0, distance: Double($0))
        }
        let api = RepeatingSummarySyncAPI(drives: repeated)
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertFalse(success)
        let snapshot = await stores.snapshot()
        let requestedPages = await api.drivePageRequests
        XCTAssertEqual(snapshot.driveSummaries.count, SyncCoordinator.summaryPageSize)
        XCTAssertNil(snapshot.state)
        XCTAssertEqual(requestedPages, [1, 2])
    }

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

    func testSyncSummaryPersistsDriveRatedRangeForCachedDashboard() async throws {
        let api = FakeSyncAPI(
            drives: [
                DriveData(
                    driveId: 10,
                    carId: 1,
                    startDate: "2026-01-01T08:00:00Z",
                    endDate: "2026-01-01T08:30:00Z",
                    distance: 26.5,
                    durationMin: 40,
                    rangeRated: DriveRange(startRange: 380, endRange: 342, rangeDiff: 38)
                )
            ],
            charges: []
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        _ = try await coordinator.syncCar(carId: 1)

        let snapshot = await stores.snapshot()
        let record = try XCTUnwrap(snapshot.driveSummaries.first)
        XCTAssertEqual(record.startRatedRangeKm, 380)
        XCTAssertEqual(record.endRatedRangeKm, 342)
    }

    func testSyncSummaryPersistsGeographyAndContextForOfflineInsights() async throws {
        let api = FakeSyncAPI(
            drives: [
                DriveData(
                    driveId: 10,
                    carId: 1,
                    startDate: "2026-01-01T08:00:00Z",
                    endDate: "2026-01-01T08:30:00Z",
                    distance: 26.5,
                    durationMin: 40,
                    startAddress: "测试住宅, 湖南, 中国",
                    endAddress: "测试公司, 湖南, 中国",
                    averageSpeed: 39,
                    outsideTempAvg: 18
                )
            ],
            charges: []
        )
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        _ = try await coordinator.syncCar(carId: 1)

        let snapshot = await stores.snapshot()
        let record = try XCTUnwrap(snapshot.driveSummaries.first)
        XCTAssertEqual(record.startAddress, "测试住宅, 湖南, 中国")
        XCTAssertEqual(record.endAddress, "测试公司, 湖南, 中国")
        XCTAssertEqual(record.speedAvg, 39)
        XCTAssertEqual(record.outsideTempAvg, 18)
    }

    func testSyncFetchesSummariesBeforeDetailsAndEnqueuesGeocode() async throws {
        let driveStart = SyntheticCoordinates.point()
        let driveEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let api = FakeSyncAPI(
            drives: [.fixture(id: 10, distance: 12)],
            charges: [.fixture(id: 20, energyAdded: 4)],
            driveDetails: [
                10: SyncDriveDetail(
                    driveId: 10,
                    positions: [
                        SyncDrivePosition(latitude: driveStart.latitude, longitude: driveStart.longitude, elevation: 10, insideTemp: 21, outsideTemp: 12, power: 20, isClimateOn: true),
                        SyncDrivePosition(latitude: driveEnd.latitude, longitude: driveEnd.longitude, elevation: 15, insideTemp: 22, outsideTemp: 14, power: -30)
                    ],
                    energyConsumedNet: 2.4,
                    consumptionNet: 200,
                    energySource: DriveEnergySource.api.rawValue
                )
            ],
            chargeDetails: [
                20: SyncChargeDetail(
                    chargeId: 20,
                    latitude: driveEnd.latitude,
                    longitude: driveEnd.longitude,
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
        XCTAssertEqual(snapshot.driveAggregates.first?.energyConsumedNet, 2.4)
        XCTAssertEqual(snapshot.driveAggregates.first?.consumptionNet, 200)
        XCTAssertEqual(snapshot.driveAggregates.first?.energySource, DriveEnergySource.api.rawValue)
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
        XCTAssertEqual(Set(snapshot.operations.prefix(2)), Set([
            "upsertDriveSummaries", "upsertChargeSummaries"
        ]))
        XCTAssertEqual(Array(snapshot.operations.dropFirst(2)), [
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

    func testCancellationWhileSummaryRequestFinishesDoesNotPersistOrShowFailure() async throws {
        let api = CancellationIgnoringSummarySyncAPI()
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let task = Task {
            try await coordinator.syncCar(carId: 1)
        }
        await api.waitUntilDriveRequestStarts()
        task.cancel()
        await api.releaseDriveRequest()

        let success = try await task.value
        let snapshot = await stores.snapshot()
        let progress = await coordinator.progress(for: 1)

        XCTAssertFalse(success)
        XCTAssertTrue(snapshot.driveSummaries.isEmpty)
        XCTAssertNil(snapshot.state)
        XCTAssertEqual(progress?.phase, .syncingSummaries)
    }

    func testCancellationWhileDetailRequestFinishesDoesNotPersistAggregateOrShowFailure() async throws {
        let api = CancellationIgnoringDetailSyncAPI()
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let task = Task {
            try await coordinator.syncCar(carId: 1)
        }
        await api.waitUntilDetailRequestStarts()
        task.cancel()
        await api.releaseDetailRequest()

        let success = try await task.value
        let snapshot = await stores.snapshot()
        let progress = await coordinator.progress(for: 1)

        XCTAssertFalse(success)
        XCTAssertEqual(snapshot.driveSummaries.map(\.driveId), [10])
        XCTAssertTrue(snapshot.driveAggregates.isEmpty)
        XCTAssertEqual(snapshot.state?.summariesSynced, true)
        XCTAssertEqual(progress?.phase, .syncingDriveDetails)
    }

    func testDriveDetailFailureLeavesRecordUnprocessedForRetry() async throws {
        let location = SyntheticCoordinates.point()
        let api = FakeSyncAPI(
            drives: [
                .fixture(id: 10, distance: 12),
                .fixture(id: 11, distance: 18)
            ],
            charges: [],
            driveDetails: [
                10: SyncDriveDetail(driveId: 10, positions: [
                    SyncDrivePosition(latitude: location.latitude, longitude: location.longitude)
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
        let location = SyntheticCoordinates.point()
        let api = FakeSyncAPI(
            drives: [],
            charges: [
                .fixture(id: 20, energyAdded: 4),
                .fixture(id: 21, energyAdded: 6)
            ],
            chargeDetails: [
                20: SyncChargeDetail(
                    chargeId: 20,
                    latitude: location.latitude,
                    longitude: location.longitude,
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

    func testHistorySyncLeavesCapacityForInteractiveDetailRequests() async throws {
        let probe = SyncConcurrencyProbe()
        let api = ConcurrentDetailSyncAPI(probe: probe)
        let stores = InMemorySyncStores()
        let coordinator = SyncCoordinator(api: api, stores: stores, geocodingService: FakeGeocodingService())

        let success = try await coordinator.syncCar(carId: 1)

        XCTAssertTrue(success)
        let peak = await probe.peak
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, 3)
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
    private let maximumPageSize: Int?
    private let lock = NSLock()
    private var recordedDrivePages: [Int] = []
    private var recordedDrivePageSizes: [Int] = []
    private var recordedChargePages: [Int] = []

    var drivePageRequests: [Int] { lock.withLock { recordedDrivePages } }
    var drivePageSizes: [Int] { lock.withLock { recordedDrivePageSizes } }
    var chargePageRequests: [Int] { lock.withLock { recordedChargePages } }

    init(
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        driveDetails: [Int: SyncDriveDetail] = [:],
        chargeDetails: [Int: SyncChargeDetail] = [:],
        drivesResult: APIResult<[DriveData]>? = nil,
        chargesResult: APIResult<[ChargeData]>? = nil,
        maximumPageSize: Int? = nil
    ) {
        self.drivesResult = drivesResult ?? .success(drives)
        self.chargesResult = chargesResult ?? .success(charges)
        self.driveDetails = driveDetails
        self.chargeDetails = chargeDetails
        self.maximumPageSize = maximumPageSize
    }

    func drives(carId _: Int, page: Int, show: Int) async -> APIResult<[DriveData]> {
        lock.withLock {
            recordedDrivePages.append(page)
            recordedDrivePageSizes.append(show)
        }
        return Self.page(
            drivesResult,
            number: page,
            size: maximumPageSize.map { min(show, $0) } ?? show
        )
    }

    func charges(carId _: Int, page: Int, show: Int) async -> APIResult<[ChargeData]> {
        lock.withLock { recordedChargePages.append(page) }
        return Self.page(
            chargesResult,
            number: page,
            size: maximumPageSize.map { min(show, $0) } ?? show
        )
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<SyncDriveDetail> {
        driveDetails[driveId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId: Int) async -> APIResult<SyncChargeDetail> {
        chargeDetails[chargeId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    private static func page<T>(_ result: APIResult<[T]>, number: Int, size: Int) -> APIResult<[T]> {
        switch result {
        case let .failure(error):
            return .failure(error)
        case let .success(items):
            let start = (number - 1) * size
            guard start < items.count else { return .success([]) }
            return .success(Array(items[start..<min(start + size, items.count)]))
        }
    }
}

private struct ConcurrentDetailSyncAPI: SyncAPIProviding {
    let probe: SyncConcurrencyProbe

    func drives(carId _: Int, page: Int, show _: Int) async -> APIResult<[DriveData]> {
        guard page == 1 else { return .success([]) }
        return .success((1...4).map { DriveData.fixture(id: $0, distance: Double($0)) })
    }

    func charges(carId _: Int, page _: Int, show _: Int) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<SyncDriveDetail> {
        await probe.begin()
        try? await Task.sleep(for: .milliseconds(50))
        await probe.end()
        return .success(SyncDriveDetail(driveId: driveId, positions: []))
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<SyncChargeDetail> {
        .failure(.emptyBody)
    }
}

private actor RepeatingSummarySyncAPI: SyncAPIProviding {
    private let repeatedDrives: [DriveData]
    private(set) var drivePageRequests: [Int] = []

    init(drives: [DriveData]) {
        repeatedDrives = drives
    }

    func drives(carId _: Int, page: Int, show _: Int) async -> APIResult<[DriveData]> {
        drivePageRequests.append(page)
        return .success(repeatedDrives)
    }

    func charges(carId _: Int, page _: Int, show _: Int) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<SyncDriveDetail> {
        .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<SyncChargeDetail> {
        .failure(.emptyBody)
    }
}

private actor CancellationIgnoringSummarySyncAPI: SyncAPIProviding {
    private var driveRequestStarted = false
    private var driveRequestRelease: CheckedContinuation<Void, Never>?

    func drives(carId _: Int, page _: Int, show _: Int) async -> APIResult<[DriveData]> {
        driveRequestStarted = true
        await withCheckedContinuation { continuation in
            driveRequestRelease = continuation
        }
        return .success([.fixture(id: 10, distance: 12)])
    }

    func charges(carId _: Int, page _: Int, show _: Int) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<SyncDriveDetail> {
        .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<SyncChargeDetail> {
        .failure(.emptyBody)
    }

    func waitUntilDriveRequestStarts() async {
        while !driveRequestStarted {
            await Task.yield()
        }
    }

    func releaseDriveRequest() {
        driveRequestRelease?.resume()
        driveRequestRelease = nil
    }
}

private actor CancellationIgnoringDetailSyncAPI: SyncAPIProviding {
    private var detailRequestStarted = false
    private var detailRequestRelease: CheckedContinuation<Void, Never>?

    func drives(carId _: Int, page: Int, show _: Int) async -> APIResult<[DriveData]> {
        page == 1 ? .success([.fixture(id: 10, distance: 12)]) : .success([])
    }

    func charges(carId _: Int, page _: Int, show _: Int) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<SyncDriveDetail> {
        detailRequestStarted = true
        await withCheckedContinuation { continuation in
            detailRequestRelease = continuation
        }
        return .success(SyncDriveDetail(driveId: driveId, positions: []))
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<SyncChargeDetail> {
        .failure(.emptyBody)
    }

    func waitUntilDetailRequestStarts() async {
        while !detailRequestStarted {
            await Task.yield()
        }
    }

    func releaseDetailRequest() {
        detailRequestRelease?.resume()
        detailRequestRelease = nil
    }
}

private actor SyncConcurrencyProbe {
    private var active = 0
    private(set) var peak = 0

    func begin() {
        active += 1
        peak = max(peak, active)
    }

    func end() {
        active -= 1
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
        guard !records.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: driveSummaries.map { ($0.driveId, $0) })
        for record in records { byID[record.driveId] = record }
        driveSummaries = byID.values.sorted { $0.driveId < $1.driveId }
        operations.append("upsertDriveSummaries")
    }

    func upsertChargeSummaries(_ records: [ChargeSummaryRecord]) async throws {
        guard !records.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: chargeSummaries.map { ($0.chargeId, $0) })
        for record in records { byID[record.chargeId] = record }
        chargeSummaries = byID.values.sorted { $0.chargeId < $1.chargeId }
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
                ? ChargeSummaryRecord(
                    chargeId: record.chargeId,
                    carId: record.carId,
                    startDate: record.startDate,
                    endDate: record.endDate,
                    chargeEnergyAdded: record.chargeEnergyAdded,
                    cost: record.cost,
                    chargeEnergyUsed: record.chargeEnergyUsed,
                    startBatteryLevel: record.startBatteryLevel,
                    endBatteryLevel: record.endBatteryLevel,
                    startRatedRangeKm: record.startRatedRangeKm,
                    endRatedRangeKm: record.endRatedRangeKm,
                    odometerKm: record.odometerKm,
                    schemaVersion: SchemaVersion.current
                )
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
