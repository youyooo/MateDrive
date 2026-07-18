import XCTest
@testable import MateDroidIOS

final class BackgroundRefreshWorkRunnerTests: XCTestCase {
    func testSuccessfulRefreshRequiresHistoryAndVehicleStatus() async {
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { true }
        )

        let report = await runner.run()

        XCTAssertTrue(report.isSuccessful)
        XCTAssertTrue(report.vehicleStatusRefreshed)
        XCTAssertFalse(report.wasCancelled)
    }

    func testVehicleStatusFailureMakesBackgroundRefreshFail() async {
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { false }
        )

        let report = await runner.run()

        XCTAssertFalse(report.isSuccessful)
        XCTAssertFalse(report.vehicleStatusRefreshed)
    }

    func testCancellationSkipsVehicleStatusRefresh() async {
        let counter = BackgroundRefreshCounter()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: SlowBackgroundHistoryRunner(),
            refreshVehicleStatus: {
                await counter.increment()
                return true
            }
        )

        let task = Task { await runner.run() }
        task.cancel()
        let report = await task.value
        let refreshCount = await counter.value

        XCTAssertTrue(report.wasCancelled)
        XCTAssertFalse(report.isSuccessful)
        XCTAssertEqual(refreshCount, 0)
    }

    func testDataPreloaderCachesExplicitSleepIntervalsWhenStateHistoryIsAvailable() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient(stateHistoryBody: #"""
        {"data":{"states":[
          {"state":"asleep","start_date":"2026-07-15T00:00:00Z","end_date":"2026-07-15T02:00:00Z"},
          {"state":"online","start_date":"2026-07-15T03:00:00Z","end_date":"2026-07-15T04:00:00Z"},
          {"state":"asleep","start_date":"not-a-date","end_date":"2026-07-15T06:00:00Z"},
          {"state":"asleep","start_date":"2026-07-16T00:00:00Z","end_date":null}
        ]}}
        """#)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let stateHistoryPath = try XCTUnwrap(requestedPaths.first { $0.hasPrefix("/api/v1/cars/7/states?") })
        let stateHistoryURL = try XCTUnwrap(URL(string: "https://teslamate.example\(stateHistoryPath)"))
        let queryItems = try XCTUnwrap(URLComponents(url: stateHistoryURL, resolvingAgainstBaseURL: false)?.queryItems)
        let monthStart = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: now)?.start)
        let formatter = ISO8601DateFormatter()
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertEqual(queryItems.map(\.name), ["startDate", "endDate"])
        XCTAssertEqual(queryItems.map(\.value), [formatter.string(from: monthStart), formatter.string(from: now)])
        XCTAssertEqual(records, [
            SleepIntervalRecord(carId: 7, startDate: "2026-07-15T00:00:00Z", endDate: "2026-07-15T02:00:00Z"),
            SleepIntervalRecord(carId: 7, startDate: "2026-07-16T00:00:00Z", endDate: "2026-07-17T12:00:00Z")
        ])
    }

    func testCancellingStateHistoryResponseDoesNotCountSuccessOrWriteSleepIntervals() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3GatedStateHistoryHTTPClient()
        let store = Task3RecordingSleepIntervalStore()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            sleepIntervalStore: store,
            now: { now }
        )

        let task = Task { await preloader.preload(force: true) }
        await client.waitUntilStateHistoryRequested()
        task.cancel()
        await client.releaseStateHistoryResponse()
        let report = await task.value
        let savedRecords = await store.savedRecords

        XCTAssertEqual(report.successfulEndpointCount, 1)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testDataPreloaderSkipsSleepHistoryWhenCachedProfileDoesNotSupportIt() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .unavailable)
        let client = Task3StateHistoryHTTPClient()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertFalse(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
        XCTAssertTrue(records.isEmpty)
    }

    func testDataPreloaderContinuesWhenOptionalSleepHistoryRequestFails() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient(stateHistoryStatusCode: 500)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertGreaterThan(report.successfulEndpointCount, 0)
        XCTAssertTrue(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
        XCTAssertTrue(records.isEmpty)
    }

    func testDataPreloaderContinuesWhenSavingSleepHistoryFails() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            sleepIntervalStore: Task3FailingSleepIntervalStore(),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(report.didRun)
        XCTAssertGreaterThan(report.successfulEndpointCount, 0)
        XCTAssertTrue(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
    }

    func testDataPreloaderResumesIncompleteCachePastDuplicatePages() async {
        let client = PartialActivityRetryHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let partial = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertEqual(partial?.state.items.map(\.stableID), ["drive-2"])
        XCTAssertEqual(partial?.state.loadedPageCount, 1)
        XCTAssertFalse(partial?.state.historyFullyLoaded == true)

        _ = await preloader.preload(force: true)
        let complete = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200",
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200"
        ])
        XCTAssertEqual(complete?.state.items.map(\.stableID), ["drive-2", "charge-1"])
        XCTAssertEqual(complete?.state.loadedPageCount, 2)
        XCTAssertTrue(complete?.state.historyFullyLoaded == true)
        XCTAssertFalse(complete?.state.hasMore == true)
    }

    func testDataPreloaderIgnoresDegradedSinglePageMetadataForFullActivityPage() async {
        let client = DegradedSinglePageActivityHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200"
        ])
        XCTAssertEqual(snapshot?.state.items.count, 200)
        XCTAssertEqual(snapshot?.state.loadedPageCount, 1)
        XCTAssertTrue(snapshot?.state.paginationIsDegraded == true)
        XCTAssertTrue(snapshot?.state.hasMore == true)
        XCTAssertFalse(snapshot?.state.historyFullyLoaded == true)
    }

    func testDataPreloaderKeepsStalledDegradedFullPagePartial() async {
        let client = RepeatingDegradedActivityHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        _ = await preloader.preload(force: true)
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200",
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200"
        ])
        XCTAssertEqual(snapshot?.state.items.count, 200)
        XCTAssertEqual(snapshot?.state.loadedPageCount, 1)
        XCTAssertNil(snapshot?.state.historyContinuityAnchorID)
        XCTAssertTrue(snapshot?.state.paginationIsDegraded == true)
        XCTAssertFalse(snapshot?.state.hasMore == true)
        XCTAssertFalse(snapshot?.state.historyFullyLoaded == true)
        XCTAssertFalse(snapshot?.state.historyLoadCapped == true)
    }

    func testDataPreloaderRejectsContradictoryPositivePaginationMetadata() async {
        let client = ContradictoryPositivePaginationHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200"
        ])
        XCTAssertEqual(snapshot?.state.items.count, 200)
        XCTAssertEqual(snapshot?.state.loadedPageCount, 1)
        XCTAssertTrue(snapshot?.state.paginationIsDegraded == true)
        XCTAssertFalse(snapshot?.state.historyFullyLoaded == true)
    }

    func testDataPreloaderKeepsIncrementalHistoryPartialUntilItBridgesCompleteCache() async {
        let client = IncrementalActivityContinuityHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        var completeState = ActivitiesState()
        completeState.items = [TeslaMateActivity(id: 1, type: "charge", startDate: "2026-07-01T00:00:00Z")]
        completeState.loadedPageCount = 4
        completeState.historyFullyLoaded = true
        await cache.save(
            ActivitiesCacheSnapshot(state: completeState),
            serverURL: settings.serverURL,
            carId: 7
        )
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let partial = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertEqual(partial?.state.items.count, 201)
        XCTAssertEqual(partial?.state.loadedPageCount, 1)
        XCTAssertEqual(partial?.state.historyContinuityAnchorID, "charge-1")
        XCTAssertTrue(partial?.state.hasMore == true)
        XCTAssertFalse(partial?.state.historyFullyLoaded == true)

        _ = await preloader.preload(force: true)
        let complete = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200",
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200"
        ])
        XCTAssertEqual(complete?.state.items.count, 201)
        XCTAssertEqual(complete?.state.loadedPageCount, 2)
        XCTAssertEqual(complete?.state.historyContinuityAnchorID, complete?.state.items.first?.stableID)
        XCTAssertNotEqual(complete?.state.historyContinuityAnchorID, "charge-1")
        XCTAssertTrue(complete?.state.historyFullyLoaded == true)
        XCTAssertFalse(complete?.state.hasMore == true)
    }

    func testDataPreloaderPersistsTrustedEmptyHistoryForSmartActivityLoader() async {
        let client = EmptyActivityHistoryHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let settingsStore = Task3PreloadSettingsStore(settings: settings)
        let preloader = AppDataPreloader(
            settingsStore: settingsStore,
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let cached = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let loader = CachedSmartActivitySourceLoader(
            activitiesCache: cache,
            sleepIntervalStore: Task3RecordingSleepIntervalStore(),
            settingsStore: settingsStore,
            chargeCostOverrideStore: EmptyChargeCostOverrideStore(),
            tariffCatalog: {
                RegionalChargingTariffCatalog(version: 1, generatedAt: "2026-07-18", regions: [])
            }
        )
        let source = try? await loader.snapshot(carId: 7)

        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.state.items.isEmpty == true)
        XCTAssertTrue(cached?.state.historyFullyLoaded == true)
        XCTAssertNil(cached?.state.historyContinuityAnchorID)
        XCTAssertNotNil(source)
        XCTAssertTrue(source?.activities.isEmpty == true)
        XCTAssertTrue(source?.historyFullyLoaded == true)
    }

    func testActivitiesCacheOnlyAllowsStrictMergedPartialToDowngradeCompleteHistory() async {
        let cache = ActivitiesStateCache(maximumAge: 60)
        let serverURL = "https://teslamate.example"
        var complete = ActivitiesState()
        complete.items = [
            TeslaMateActivity(id: 1, type: "drive"),
            TeslaMateActivity(id: 2, type: "charge")
        ]
        complete.loadedPageCount = 4
        complete.historyFullyLoaded = true
        await cache.save(ActivitiesCacheSnapshot(state: complete), serverURL: serverURL, carId: 7)

        var mergedPartial = complete
        mergedPartial.items.append(TeslaMateActivity(id: 3, type: "park"))
        mergedPartial.loadedPageCount = 1
        mergedPartial.historyFullyLoaded = false
        mergedPartial.historyContinuityAnchorID = "drive-1"
        await cache.save(ActivitiesCacheSnapshot(state: mergedPartial), serverURL: serverURL, carId: 7)

        var losingPartial = mergedPartial
        losingPartial.items.removeFirst()
        losingPartial.loadedPageCount = 2
        await cache.save(ActivitiesCacheSnapshot(state: losingPartial), serverURL: serverURL, carId: 7)

        var regressedPartial = mergedPartial
        regressedPartial.loadedPageCount = 0
        await cache.save(ActivitiesCacheSnapshot(state: regressedPartial), serverURL: serverURL, carId: 7)
        let restored = await cache.load(serverURL: serverURL, carId: 7, now: Date())

        XCTAssertEqual(Set(restored?.state.items.map(\.stableID) ?? []), ["drive-1", "charge-2", "park-3"])
        XCTAssertEqual(restored?.state.loadedPageCount, 1)
        XCTAssertEqual(restored?.state.historyContinuityAnchorID, "drive-1")
        XCTAssertFalse(restored?.state.historyFullyLoaded == true)
    }

    func testDataPreloaderCapsDegradedActivityPaginationAtMaximumPageCount() async {
        let client = EndlessDegradedActivityHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: settings),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let activityRequestCount = await client.requestedPaths.filter { $0.contains("/activities?") }.count

        XCTAssertEqual(activityRequestCount, 250)
        XCTAssertEqual(snapshot?.state.items.count, 250)
        XCTAssertEqual(snapshot?.state.loadedPageCount, 250)
        XCTAssertTrue(snapshot?.state.historyLoadCapped == true)
        XCTAssertTrue(snapshot?.state.hasMore == true)
        XCTAssertFalse(snapshot?.state.historyFullyLoaded == true)
    }

    func testBackgroundRunnerIndexesOnlyAfterHistoryAndStatusFinish() async {
        let order = BackgroundIndexCallOrderRecorder()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: OrderedBackgroundHistoryRunner(order: order),
            refreshVehicleStatus: {
                await order.append("status")
                return true
            },
            rebuildSmartActivities: { carIds in
                await order.append("index-\(carIds)")
                return true
            }
        )

        let report = await runner.run()
        let lastCall = await order.last

        XCTAssertEqual(lastCall, "index-[1]")
        XCTAssertTrue(report.smartActivitiesIndexed)
        XCTAssertTrue(report.isSuccessful)
    }

    func testBackgroundRunnerStartsHistoryAndStatusInParallelBeforeIndexing() async {
        let gate = ParallelBackgroundWorkGate()
        let order = BackgroundIndexCallOrderRecorder()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: ParallelBackgroundHistoryRunner(gate: gate, order: order),
            refreshVehicleStatus: {
                await gate.markStarted("status")
                await gate.waitForRelease()
                await order.append("status-finished")
                return true
            },
            rebuildSmartActivities: { carIds in
                await order.append("index-\(carIds)")
                return true
            }
        )

        let task = Task { await runner.run() }
        await gate.waitUntilBothStarted()
        let started = await gate.startedNames
        XCTAssertEqual(started, Set(["history", "status"]))

        await gate.release()
        let report = await task.value
        let lastCall = await order.last
        XCTAssertEqual(lastCall, "index-[1]")
        XCTAssertTrue(report.smartActivitiesIndexed)
    }

    func testCancellationAfterHistoryFinishesSkipsIndexAndReportsFalse() async {
        let history = CancellationAfterHistoryRunner()
        let statusGate = CancellationStatusGate()
        let indexCounter = BackgroundRefreshCounter()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: history,
            refreshVehicleStatus: {
                await statusGate.waitForRelease()
                return true
            },
            rebuildSmartActivities: { _ in
                await indexCounter.increment()
                return true
            }
        )

        let task = Task { await runner.run() }
        await history.waitUntilFinished()
        task.cancel()
        await statusGate.release()
        let report = await task.value
        let indexCount = await indexCounter.value

        XCTAssertTrue(report.wasCancelled)
        XCTAssertFalse(report.smartActivitiesIndexed)
        XCTAssertEqual(indexCount, 0)
    }

    func testIndexingFailureMakesBackgroundRefreshFail() async {
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { true },
            rebuildSmartActivities: { _ in false }
        )

        let report = await runner.run()

        XCTAssertFalse(report.smartActivitiesIndexed)
        XCTAssertFalse(report.isSuccessful)
    }
}

private actor BackgroundIndexCallOrderRecorder {
    private var values: [String] = []
    var last: String? { values.last }
    func append(_ value: String) { values.append(value) }
}

private struct OrderedBackgroundHistoryRunner: HistorySyncRunning {
    let order: BackgroundIndexCallOrderRecorder

    func run() async -> HistorySyncReport {
        await order.append("history")
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }
}

private struct ParallelBackgroundHistoryRunner: HistorySyncRunning {
    let gate: ParallelBackgroundWorkGate
    let order: BackgroundIndexCallOrderRecorder

    func run() async -> HistorySyncReport {
        await gate.markStarted("history")
        await gate.waitForRelease()
        await order.append("history-finished")
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }
}

private actor CancellationAfterHistoryRunner: HistorySyncRunning {
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run() async -> HistorySyncReport {
        finished = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }

    func waitUntilFinished() async {
        guard !finished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor CancellationStatusGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor ParallelBackgroundWorkGate {
    private(set) var startedNames: Set<String> = []
    private var released = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted(_ name: String) {
        startedNames.insert(name)
        guard startedNames.count >= 2 else { return }
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
    }

    func waitUntilBothStarted() async {
        guard startedNames.count >= 2 else {
            await withCheckedContinuation { startedWaiters.append($0) }
            return
        }
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private struct StubBackgroundHistoryRunner: HistorySyncRunning {
    let report: HistorySyncReport
    func run() async -> HistorySyncReport { report }
}

private struct SlowBackgroundHistoryRunner: HistorySyncRunning {
    func run() async -> HistorySyncReport {
        try? await Task.sleep(for: .seconds(1))
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }
}

private actor BackgroundRefreshCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct Task3StaticDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase { database }
}

private struct Task3FailingSleepIntervalStore: SleepIntervalStoring {
    func upsertAll(_: [SleepIntervalRecord]) async throws {
        throw SQLiteError.executionFailed("Storage unavailable")
    }

    func records(carId _: Int, start _: String, end _: String) async throws -> [SleepIntervalRecord] {
        []
    }
}

private actor Task3RecordingSleepIntervalStore: SleepIntervalStoring {
    private(set) var savedRecords: [SleepIntervalRecord] = []

    func upsertAll(_ records: [SleepIntervalRecord]) async throws {
        savedRecords.append(contentsOf: records)
    }

    func records(carId _: Int, start _: String, end _: String) async throws -> [SleepIntervalRecord] {
        savedRecords
    }
}

private func saveTask3StateHistoryProfile(
    in database: SQLiteDatabase,
    carId: Int,
    at checkedAt: Date,
    state: TeslaMateCapabilityState
) async throws {
    try await TeslaMateServerProfileStore(database: database).save(TeslaMateServerProfile(
        serverKey: TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example")!),
        carId: carId,
        version: TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: nil, buildInfo: nil),
        capabilities: [
            .stateHistory: TeslaMateCapabilityStatus(
                state: state,
                source: .cached,
                checkedAt: checkedAt
            )
        ],
        checkedAt: checkedAt
    ))
}

private actor Task3StateHistoryHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private let stateHistoryBody: String
    private let stateHistoryStatusCode: Int

    init(
        stateHistoryBody: String = #"{"data":{"states":[]}}"#,
        stateHistoryStatusCode: Int = 200
    ) {
        self.stateHistoryBody = stateHistoryBody
        self.stateHistoryStatusCode = stateHistoryStatusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let isStateHistory = url.path.hasSuffix("/states")
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if isStateHistory {
            body = stateHistoryBody
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: isStateHistory ? stateHistoryStatusCode : 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private actor Task3GatedStateHistoryHTTPClient: HTTPClient {
    private var stateHistoryRequested = false
    private var stateHistoryReleased = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/states") {
            stateHistoryRequested = true
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
            if !stateHistoryReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
            body = #"{"data":{"states":[{"state":"asleep","start_date":"2026-07-15T00:00:00Z","end_date":"2026-07-15T02:00:00Z"}]}}"#
            statusCode = 200
        } else {
            body = #"{}"#
            statusCode = 500
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }

    func waitUntilStateHistoryRequested() async {
        guard !stateHistoryRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseStateHistoryResponse() {
        stateHistoryReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor PartialActivityRetryHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private var secondPageAttemptCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        let statusCode: Int

        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 1 {
            body = #"{"data":[{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"page":1,"limit":1,"totalPages":2,"totalRecords":2}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 2 {
            secondPageAttemptCount += 1
            if secondPageAttemptCount == 1 {
                body = #"{"error":"temporary failure"}"#
                statusCode = 500
            } else {
                body = #"{"data":[{"id":1,"type":"charge","startDate":"2026-07-01T00:00:00Z"}],"pagination":{"page":2,"limit":1,"totalPages":2,"totalRecords":2}}"#
                statusCode = 200
            }
        } else {
            body = #"{}"#
            statusCode = 200
        }

        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor DegradedSinglePageActivityHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 1 {
            let activities = (1 ... 200)
                .map { #"{"id":\#($0),"type":"drive"}"# }
                .joined(separator: ",")
            body = #"{"data":[\#(activities)],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":0}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 2 {
            body = #"{"error":"temporary failure"}"#
            statusCode = 500
        } else {
            body = #"{}"#
            statusCode = 200
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor RepeatingDegradedActivityHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities") {
            let activities = (1 ... 200)
                .map { #"{"id":\#($0),"type":"drive"}"# }
                .joined(separator: ",")
            body = #"{"data":[\#(activities)],"pagination":{"page":1,"limit":200,"totalPages":9999,"totalRecords":0}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor ContradictoryPositivePaginationHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 1 {
            let activities = (1 ... 200)
                .map { #"{"id":\#($0),"type":"drive"}"# }
                .joined(separator: ",")
            body = #"{"data":[\#(activities)],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":201}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 2 {
            body = #"{"error":"temporary failure"}"#
            statusCode = 500
        } else {
            body = #"{}"#
            statusCode = 200
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor EmptyActivityHistoryHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities") {
            body = #"{"data":[],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":0}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor IncrementalActivityContinuityHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private var secondPageAttemptCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 1 {
            let activities = (2 ... 201)
                .map { #"{"id":\#($0),"type":"drive","startDate":"2026-07-02T00:00:00Z"}"# }
                .joined(separator: ",")
            body = #"{"data":[\#(activities)],"pagination":{"page":1,"limit":200,"totalPages":2,"totalRecords":201}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/activities"), page == 2 {
            secondPageAttemptCount += 1
            if secondPageAttemptCount == 1 {
                body = #"{"error":"temporary failure"}"#
                statusCode = 500
            } else {
                body = #"{"data":[{"id":1,"type":"charge","startDate":"2026-07-01T00:00:00Z"}],"pagination":{"page":2,"limit":200,"totalPages":2,"totalRecords":201}}"#
                statusCode = 200
            }
        } else {
            body = #"{}"#
            statusCode = 200
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor EndlessDegradedActivityHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities"), let page {
            body = #"{"data":[{"id":\#(page),"type":"drive"}],"pagination":{"page":1,"limit":1,"totalPages":9999,"totalRecords":0}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor Task3PreloadSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private struct Task3PreloadSecretStore: SecretStoring {
    func get(_ key: String) async throws -> String? { nil }
    func set(_ value: String, for key: String) async throws {}
    func remove(_ key: String) async throws {}
}
