import XCTest
@testable import MateDriveApp

@MainActor
final class CompareDrivesViewModelTests: XCTestCase {
    func testCompareDrivesShowsBaseBeforeSlowHistoryListFinishes() async {
        let base = DriveDetail(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            startAddress: "Start",
            endAddress: "End",
            distance: 20,
            durationMin: 30
        )
        let api = DelayedCompareDriveListAPI(base: base)
        let viewModel = CompareDrivesViewModel(api: api)

        let loadTask = Task { await viewModel.load(carId: 1, baseDriveId: 10) }
        await api.waitUntilDrivesRequested()
        for _ in 0 ..< 100 where viewModel.state.rows.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [10])
        XCTAssertFalse(viewModel.state.isLoading)
        let requestedShow = await api.requestedShow
        XCTAssertEqual(requestedShow, VehicleHistoryPaginator.pageSize)

        await api.releaseDrives()
        await loadTask.value
    }

    func testHistoryPaginatorLoadsEveryPageAndRemovesDuplicateIdentifiers() async {
        let recorder = HistoryPageRecorder(results: [
            .success((1 ... 200).map { DriveData(driveId: $0) }),
            .success([DriveData(driveId: 200), DriveData(driveId: 201)]),
            .success([])
        ])

        let result = await VehicleHistoryPaginator.drives { page, show in
            await recorder.load(page: page, show: show)
        }

        guard case let .success(drives) = result else {
            return XCTFail("Expected complete paginated history")
        }
        XCTAssertEqual(drives.compactMap(\.driveId), Array(1 ... 201))
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.page), [1, 2, 3])
        XCTAssertEqual(requests.map(\.show), [200, 200, 200])
    }

    func testHistoryPaginatorKeepsLoadingWhenServerCapsPagesBelowRequestedSize() async {
        let recorder = HistoryPageRecorder(results: [
            .success((1 ... 100).map { DriveData(driveId: $0) }),
            .success((101 ... 153).map { DriveData(driveId: $0) }),
            .success([])
        ])

        let result = await VehicleHistoryPaginator.drives { page, show in
            await recorder.load(page: page, show: show)
        }

        guard case let .success(drives) = result else {
            return XCTFail("Expected complete history from server-capped pages")
        }
        XCTAssertEqual(drives.compactMap(\.driveId), Array(1 ... 153))
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.page), [1, 2, 3])
        XCTAssertEqual(requests.map(\.show), [200, 200, 200])
    }

    func testHistoryPaginatorRejectsRepeatedFullPage() async {
        let repeatedPage = (1 ... 200).map { DriveData(driveId: $0) }
        let recorder = HistoryPageRecorder(results: [.success(repeatedPage), .success(repeatedPage)])

        let result = await VehicleHistoryPaginator.drives { page, show in
            await recorder.load(page: page, show: show)
        }

        XCTAssertEqual(result.error, .invalidResponse("History pagination returned a repeated full page."))
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    func testHistoryPaginatorDoesNotReturnPartialHistoryAfterLaterFailure() async {
        let recorder = HistoryPageRecorder(results: [
            .success((1 ... 200).map { DriveData(driveId: $0) }),
            .failure(.network("offline"))
        ])

        let result = await VehicleHistoryPaginator.drives { page, show in
            await recorder.load(page: page, show: show)
        }

        XCTAssertEqual(result.error, .network("offline"))
    }

    func testHistoryPaginatorHonorsCancellationBeforeRequest() async {
        let recorder = HistoryPageRecorder(results: [.success([])])
        let task = Task {
            await VehicleHistoryPaginator.drives { page, show in
                await recorder.load(page: page, show: show)
            }
        }
        task.cancel()

        let result = await task.value

        XCTAssertEqual(result.error, .cancelled)
        let requests = await recorder.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCompareDrivesUsesLocalHistoryWithoutCallingDriveAPI() async {
        let base = DriveData(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            distance: 20,
            durationMin: 30,
            startAddress: "Start",
            endAddress: "End",
            speedAvg: 40,
            consumptionNet: 150
        )
        let comparable = DriveData(
            driveId: 11,
            startDate: "2026-07-02T08:00:00Z",
            distance: 21,
            durationMin: 28,
            startAddress: "Start",
            endAddress: "End",
            speedAvg: 45,
            consumptionNet: 140
        )
        let api = CountingCompareDriveAPI()
        let viewModel = CompareDrivesViewModel(
            api: api,
            historyProvider: CompareHistoryProvider(drives: [base, comparable])
        )

        await viewModel.load(carId: 1, baseDriveId: 10)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(Set(viewModel.state.rows.map(\.driveId)), [10, 11])
        XCTAssertEqual(viewModel.state.average.count, 2)
        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testCompareDrivesRestoresCachedContentImmediately() {
        let cache = CompareDrivesStateCache(maximumEntryCount: 2)
        let key = CompareDrivesCacheKey(serverURL: "https://example.test", carId: 1, baseDriveId: 10)
        let cachedRow = ComparableDriveRow(
            driveId: 10,
            isBase: true,
            startDate: "2026-07-01T08:00:00Z",
            startAddress: "Home",
            endAddress: "Office",
            distance: 20,
            durationMin: 30,
            efficiency: 145,
            speedAvg: 40,
            outsideTempAvg: 24
        )
        cache.save(
            CompareDrivesState(
                isLoading: false,
                rows: [cachedRow],
                average: DriveComparisonAverage(
                    efficiency: 145,
                    durationMin: 30,
                    speedAvg: 40,
                    count: 1
                ),
                sort: .efficiency,
                units: .metric
            ),
            for: key
        )

        let viewModel = CompareDrivesViewModel(
            api: CountingCompareDriveAPI(),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.rows, [cachedRow])
        XCTAssertEqual(viewModel.state.average.count, 1)

        viewModel.setSort(.duration)

        XCTAssertEqual(viewModel.state.rows, [cachedRow])
        XCTAssertEqual(viewModel.state.sort, .duration)
    }

    func testCompareDrivesCacheDoesNotCrossVehicleBoundaries() {
        let cache = CompareDrivesStateCache(maximumEntryCount: 2)
        cache.save(
            CompareDrivesState(
                isLoading: false,
                rows: [
                    ComparableDriveRow(
                        driveId: 10,
                        isBase: true,
                        startDate: "",
                        startAddress: nil,
                        endAddress: nil,
                        distance: nil,
                        durationMin: nil,
                        efficiency: nil,
                        speedAvg: nil,
                        outsideTempAvg: nil
                    )
                ]
            ),
            for: CompareDrivesCacheKey(
                serverURL: "https://example.test",
                carId: 1,
                baseDriveId: 10
            )
        )

        let otherVehicle = CompareDrivesViewModel(
            api: CountingCompareDriveAPI(),
            cacheKey: CompareDrivesCacheKey(
                serverURL: "https://example.test",
                carId: 2,
                baseDriveId: 10
            ),
            stateCache: cache
        )

        XCTAssertTrue(otherVehicle.state.isLoading)
        XCTAssertTrue(otherVehicle.state.rows.isEmpty)
    }
}

private extension APIResult {
    var error: APIError? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}

private actor HistoryPageRecorder {
    struct Request: Equatable {
        let page: Int
        let show: Int
    }

    private let results: [APIResult<[DriveData]>]
    private(set) var requests: [Request] = []

    init(results: [APIResult<[DriveData]>]) {
        self.results = results
    }

    func load(page: Int, show: Int) -> APIResult<[DriveData]> {
        requests.append(Request(page: page, show: show))
        let index = min(page - 1, results.count - 1)
        return results[index]
    }
}

private struct CompareHistoryProvider: MileageDataProviding {
    let drives: [DriveData]

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        .success(drives)
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(UnitPreferences(unitOfLength: "km"))
    }
}

private actor CountingCompareDriveAPI: DriveAPIProviding {
    private(set) var requestCount = 0

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        requestCount += 1
        return .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        requestCount += 1
        return .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        requestCount += 1
        return .failure(.emptyBody)
    }
}

private actor DelayedCompareDriveListAPI: DriveAPIProviding {
    private let base: DriveDetail
    private var drivesRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedShow: Int?

    init(base: DriveDetail) {
        self.base = base
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show: Int?) async -> APIResult<[DriveData]> {
        requestedShow = show
        drivesRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .success(base)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }

    func waitUntilDrivesRequested() async {
        guard !drivesRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseDrives() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
