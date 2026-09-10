import XCTest
@testable import MateDriveApp

@MainActor
final class WhereWasICacheFirstTests: XCTestCase {
    func testLocalDriveSummaryAppearsBeforeSlowDetailEnrichment() async {
        let drive = DriveData(
            driveId: 7,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T09:00:00Z",
            distance: 20,
            durationMin: 60,
            startAddress: "Home",
            endAddress: "Office",
            outsideTempAvg: 28
        )
        let api = SlowWhereWasIDetailAPI()
        let viewModel = WhereWasIViewModel(
            api: api,
            historyProvider: WhereWasIHistoryProvider(drives: [drive], charges: [])
        )

        let loadTask = Task {
            await viewModel.load(carId: 1, timestamp: "2026-07-01T08:42:00Z")
        }
        await api.waitUntilDetailRequested()

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.carState, .driving)
        XCTAssertEqual(viewModel.state.driveId, 7)
        XCTAssertEqual(viewModel.state.driveDistance, 20)
        XCTAssertEqual(viewModel.state.geofenceName, "Office")
        let historyRequestCount = await api.historyRequestCount
        XCTAssertEqual(historyRequestCount, 0)

        await api.releaseDetail()
        await loadTask.value
    }

    func testRepeatedEntryRestoresScopedStateAndPreservesItOnFailure() async {
        let cache = VehiclePageStateCache<WhereWasIState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://example.test",
            carId: 1,
            scope: "where-was-i:2026-07-01T10:00:00Z"
        )
        let drive = DriveData(
            driveId: 7,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T09:00:00Z",
            distance: 20,
            endAddress: "Office"
        )
        let first = WhereWasIViewModel(
            api: SlowWhereWasIDetailAPI(),
            historyProvider: WhereWasIHistoryProvider(drives: [drive], charges: []),
            cacheKey: key,
            stateCache: cache
        )

        await first.load(carId: 1, timestamp: "2026-07-01T10:00:00Z")
        XCTAssertEqual(first.state.carState, .parked)
        XCTAssertEqual(first.state.geofenceName, "Office")

        let reopened = WhereWasIViewModel(
            api: SlowWhereWasIDetailAPI(),
            historyProvider: FailingWhereWasIHistoryProvider(),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.carState, .parked)
        XCTAssertEqual(reopened.state.geofenceName, "Office")

        await reopened.load(carId: 1, timestamp: "2026-07-01T10:00:00Z")
        XCTAssertEqual(reopened.state.carState, .parked)
        XCTAssertEqual(reopened.state.geofenceName, "Office")
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testDifferentTimestampScopeDoesNotRestoreAnotherResult() async {
        let cache = VehiclePageStateCache<WhereWasIState>()
        cache.save(
            WhereWasIState(
                isLoading: false,
                carState: .parked,
                geofenceName: "Office"
            ),
            for: VehiclePageCacheKey(
                serverURL: "https://example.test",
                carId: 1,
                scope: "where-was-i:2026-07-01T10:00:00Z"
            )
        )

        let viewModel = WhereWasIViewModel(
            api: SlowWhereWasIDetailAPI(),
            historyProvider: FailingWhereWasIHistoryProvider(),
            cacheKey: VehiclePageCacheKey(
                serverURL: "https://example.test",
                carId: 1,
                scope: "where-was-i:2026-07-02T10:00:00Z"
            ),
            stateCache: cache
        )

        XCTAssertTrue(viewModel.state.isLoading)
        XCTAssertNil(viewModel.state.carState)
        XCTAssertNil(viewModel.state.geofenceName)
    }

    func testOverlappingLoadsReadHistoryOnlyOnce() async {
        let provider = SlowWhereWasIHistoryProvider()
        let viewModel = WhereWasIViewModel(
            api: SlowWhereWasIDetailAPI(),
            historyProvider: provider
        )

        let first = Task {
            await viewModel.load(carId: 1, timestamp: "2026-07-01T10:00:00Z")
        }
        await provider.waitUntilHistoryRequested()
        let second = Task {
            await viewModel.load(carId: 1, timestamp: "2026-07-01T10:00:00Z")
        }
        await Task.yield()
        await provider.release()
        await first.value
        await second.value

        let counts = await provider.requestCounts
        XCTAssertEqual(counts.drives, 1)
        XCTAssertEqual(counts.charges, 1)
        XCTAssertEqual(counts.units, 1)
    }
}

private struct WhereWasIHistoryProvider: MileageDataProviding {
    let drives: [DriveData]
    let charges: [ChargeData]

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        .success(drives)
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        .success(charges)
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(UnitPreferences(unitOfLength: "km"))
    }
}

private struct FailingWhereWasIHistoryProvider: MileageDataProviding {
    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        .failure(.emptyBody)
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        .failure(.emptyBody)
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .failure(.emptyBody)
    }
}

private actor SlowWhereWasIHistoryProvider: MileageDataProviding {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var historyRequestCount = 0
    private var driveRequests = 0
    private var chargeRequests = 0
    private var unitRequests = 0

    var requestCounts: (drives: Int, charges: Int, units: Int) {
        (driveRequests, chargeRequests, unitRequests)
    }

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        driveRequests += 1
        await suspendHistoryRequest()
        return .success([])
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        chargeRequests += 1
        await suspendHistoryRequest()
        return .success([])
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        unitRequests += 1
        return .success(UnitPreferences(unitOfLength: "km"))
    }

    func waitUntilHistoryRequested() async {
        guard historyRequestCount < 2 else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    private func suspendHistoryRequest() async {
        historyRequestCount += 1
        if historyRequestCount == 2 {
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor SlowWhereWasIDetailAPI: AnalyticsAPIProviding {
    private var detailWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var detailRequested = false
    private(set) var historyRequestCount = 0

    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> { .failure(.emptyBody) }
    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> { .failure(.emptyBody) }
    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> { .success([]) }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        historyRequestCount += 1
        return .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        historyRequestCount += 1
        return .success([])
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<DriveDetail> {
        detailRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { detailWaiters.append($0) }
        return .success(DriveDetail(driveId: driveId))
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.emptyBody) }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { .failure(.emptyBody) }

    func waitUntilDetailRequested() async {
        guard !detailRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseDetail() {
        detailWaiters.forEach { $0.resume() }
        detailWaiters.removeAll()
    }
}
