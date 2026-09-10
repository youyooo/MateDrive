import XCTest
@testable import MateDriveApp

final class BackgroundRefreshWorkRunnerTests: XCTestCase {
    func testDataPreloaderWarmsMajorPageEndpointsForSelectedVehicle() async {
        let client = PreloadRecordingHTTPClient(includesHistory: true)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            minimumInterval: 300
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(report.didRun)
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/status"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/activities?page=1&show=200"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/drives?page=1&show=200"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/charges?page=1&show=200"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/battery-health"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/stats"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/places?page=1&show=100"))
        XCTAssertTrue(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/standby-drain?") })
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/drives/107"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/charges/207"))
        XCTAssertEqual(
            requestedPaths.filter { $0.hasPrefix("/api/v1/cars/7/stats/cost-charging-detail?") }.count,
            CostReviewRange.allCases.count
        )
    }

    func testDataPreloaderUsesLocalHistoryWithoutOversizedListRequests() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        try await DriveSummaryStore(database: database).upsertAll([
            DriveSummaryRecord(
                driveId: 107,
                carId: 7,
                startDate: "2026-07-15T08:00:00Z",
                endDate: "2026-07-15T08:20:00Z",
                distance: 12,
                durationMin: 20
            )
        ])
        try await ChargeSummaryStore(database: database).upsertAll([
            ChargeSummaryRecord(
                chargeId: 207,
                carId: 7,
                startDate: "2026-07-15T20:00:00Z",
                endDate: "2026-07-15T21:00:00Z",
                chargeEnergyAdded: 18,
                cost: 9,
                durationMin: 60
            )
        ])
        let client = PreloadRecordingHTTPClient()
        let suiteName = "PreloadLocalHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let widgetStore = WidgetSnapshotStore(defaults: defaults)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            widgetSnapshotStore: widgetStore,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        _ = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let chargingTrend = try XCTUnwrap(widgetStore.vehicleSnapshots().first?.chargingTrend)

        XCTAssertFalse(requestedPaths.contains { $0.contains("show=50000") })
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/drives/107"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/charges/207"))
        XCTAssertEqual(chargingTrend.sessionCount, 1)
        XCTAssertEqual(chargingTrend.energyKWh, 18)
        XCTAssertEqual(chargingTrend.cost, 9)
    }

    func testDataPreloaderRefreshesOnlyFirstPlacePageAfterHistoricalPagesAreCached() async throws {
        let upstream = PreloadRecordingHTTPClient(placePageCount: 2)
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60, maximumAge: 60 * 60),
            namespace: "preloader-place-pages-\(UUID().uuidString)"
        )
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database)
        )

        _ = await preloader.preload(force: true)
        _ = await preloader.preload(force: true)
        let placeRequests = await upstream.requestedPaths.filter { $0.contains("/places?") }

        XCTAssertEqual(placeRequests, [
            "/api/v1/cars/7/places?page=1&show=100",
            "/api/v1/cars/7/places?page=2&show=100",
            "/api/v1/cars/7/places?page=1&show=100"
        ])
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

    func testDataPreloaderSkipsRepeatedRunInsideMinimumInterval() async {
        let client = ActivityFreshnessHTTPClient()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            minimumInterval: 300
        )

        let firstReport = await preloader.preload(force: true)
        let firstRequestCount = await client.requestedPaths.count
        let secondReport = await preloader.preload()
        let secondRequestCount = await client.requestedPaths.count

        XCTAssertTrue(firstReport.activitiesRefreshSucceeded)
        XCTAssertTrue(firstReport.canIndexSmartActivities)
        XCTAssertFalse(secondReport.didRun)
        XCTAssertTrue(secondReport.activitiesRefreshSucceeded)
        XCTAssertTrue(secondReport.canIndexSmartActivities)
        XCTAssertEqual(secondRequestCount, firstRequestCount)
    }

    func testStandaloneSkippedPreloadReportCannotIndexActivities() {
        XCTAssertFalse(AppDataPreloadReport.skipped.activitiesRefreshSucceeded)
        XCTAssertFalse(AppDataPreloadReport.skipped.canIndexSmartActivities)
    }

    func testDataPreloaderRejectsIndexingWhenAllActivityRequestsFail() async {
        let client = ActivityFreshnessHTTPClient(failedActivityCarIDs: [7])
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client
        )

        let report = await preloader.preload(force: true)

        XCTAssertTrue(report.didRun)
        XCTAssertFalse(report.activitiesRefreshSucceeded)
        XCTAssertFalse(report.canIndexSmartActivities)
        XCTAssertGreaterThan(report.successfulEndpointCount, 0)
    }

    func testDataPreloaderSkippedRunInheritsFailedActivityRefresh() async {
        let client = ActivityFreshnessHTTPClient(failedActivityCarIDs: [7])
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            minimumInterval: 300
        )

        let failedReport = await preloader.preload(force: true)
        let firstRequestCount = await client.requestedPaths.count
        let skippedReport = await preloader.preload()
        let secondRequestCount = await client.requestedPaths.count

        XCTAssertTrue(failedReport.didRun)
        XCTAssertFalse(failedReport.canIndexSmartActivities)
        XCTAssertFalse(skippedReport.didRun)
        XCTAssertFalse(skippedReport.activitiesRefreshSucceeded)
        XCTAssertFalse(skippedReport.canIndexSmartActivities)
        XCTAssertEqual(secondRequestCount, firstRequestCount)
    }

    func testDataPreloaderRequiresSuccessfulActivitiesResponseForEveryCar() async {
        let client = ActivityFreshnessHTTPClient(
            carIDs: [7, 8],
            failedActivityCarIDs: [8]
        )
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(report.didRun)
        XCTAssertFalse(report.activitiesRefreshSucceeded)
        XCTAssertFalse(report.canIndexSmartActivities)
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/activities?page=1&show=200"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/8/activities?page=1&show=200"))
    }

    func testDataPreloaderDoesNotRefetchCachedHistoricalDetails() async {
        let upstream = PreloadRecordingHTTPClient(includesHistory: true)
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60, maximumAge: 60 * 60),
            namespace: "preloader-detail-test"
        )
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client
        )

        _ = await preloader.preload(force: true)
        _ = await preloader.preload(force: true)
        let requestedPaths = await upstream.requestedPaths

        XCTAssertEqual(requestedPaths.filter { $0 == "/api/v1/cars/7/drives/107" }.count, 2)
        XCTAssertEqual(requestedPaths.filter { $0 == "/api/v1/cars/7/drives/106" }.count, 1)
        XCTAssertEqual(requestedPaths.filter { $0 == "/api/v1/cars/7/charges/207" }.count, 2)
        XCTAssertEqual(requestedPaths.filter { $0 == "/api/v1/cars/7/charges/206" }.count, 1)
    }

    func testDataPreloaderWarmsEveryVehicleInsteadOfOnlySelectedVehicle() async {
        let client = PreloadRecordingHTTPClient(carIDs: [7, 8])
        let suiteName = "PreloadWidgetSnapshots.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let widgetStore = WidgetSnapshotStore(defaults: defaults)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            widgetSnapshotStore: widgetStore
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/status"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/8/status"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/8/activities?page=1&show=200"))
        XCTAssertEqual(report.requestedEndpointCount, 54)
        XCTAssertEqual(report.successfulEndpointCount, 54)
        XCTAssertEqual(widgetStore.vehicleSnapshots().map(\.data.carName), ["Test car 7", "Test car 8"])
        XCTAssertEqual(widgetStore.vehicleSnapshots().map(\.data.batteryLevel), [67, 68])
        XCTAssertEqual(widgetStore.vehicleSnapshots().map(\.batteryTrend?.headlineText), ["93.3%", "93.3%"])
        XCTAssertEqual(widgetStore.vehicleSnapshots().map(\.chargingTrend?.sessionCount), [0, 0])
        XCTAssertEqual(widgetStore.load()?.carName, "Test car 7")
    }

    func testWidgetPreloadRequestsCurrentChargeOnlyForChargingVehicles() async throws {
        let client = PreloadRecordingHTTPClient(
            carIDs: [7, 8],
            chargingCarIDs: [7]
        )
        let suiteName = "PreloadCurrentCharge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader
        )

        let report = await preloader.preload(force: true)
        let paths = await client.requestedPaths

        XCTAssertEqual(
            paths.filter { $0 == "/api/v1/cars/7/charges/current" }.count,
            1,
            "Charging vehicle should request current charge exactly once: \(paths)"
        )
        XCTAssertEqual(
            paths.filter { $0 == "/api/v1/cars/8/charges/current" }.count,
            0,
            "Idle vehicle unexpectedly requested current charge: \(paths)"
        )
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://teslamate.example",
            carID: 7
        ))
        XCTAssertEqual(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge?.phase,
            .charging
        )
        XCTAssertEqual(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge?.energyAddedKWh,
            18.4
        )
        XCTAssertEqual(report.requestedEndpointCount, 55)
    }

    // Production break caught: background preload starts a new activity instead of updating only an already-running matching activity.
    func testBackgroundChargingUpdatesExistingActivityOnly() async throws {
        let suiteName = "BackgroundChargeActivityIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let liveActivity = BackgroundRecordingLiveActivityManager()
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(
                carIDs: [7],
                chargingCarIDs: [7]
            ),
            widgetSnapshotStore: WidgetSnapshotStore(defaults: defaults),
            widgetTimelineReloader: RecordingWidgetTimelineReloader(),
            liveActivityCoordinator: ChargeLiveActivityCoordinator(manager: liveActivity)
        )

        _ = await preloader.preload(force: true)

        let calls = await liveActivity.recordedCalls()
        let activitySnapshots = await liveActivity.recordedExistingSnapshots()
        let expectedIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://teslamate.example",
            carID: 7
        ))
        XCTAssertEqual(calls, [.updateExisting(carId: 7)])
        let activitySnapshot = try XCTUnwrap(activitySnapshots.first)
        XCTAssertEqual(activitySnapshots.count, 1)
        XCTAssertEqual(activitySnapshot.vehicleIdentifier, expectedIdentifier)
        XCTAssertEqual(activitySnapshot.batteryLevel, 67)
        XCTAssertEqual(activitySnapshot.quality, .complete)
        XCTAssertEqual(activitySnapshot.energyAddedKWh, 18.4)
        XCTAssertFalse(calls.contains { call in
            if case .startOrUpdate = call { return true }
            return false
        })
    }

    func testSuccessfulCarLoadReplacesWidgetNavigationRegistryWithoutChangingRequestCounts() async throws {
        let snapshotSuiteName = "PreloadNavigationSnapshots.\(UUID().uuidString)"
        let snapshotDefaults = try XCTUnwrap(UserDefaults(suiteName: snapshotSuiteName))
        defer { snapshotDefaults.removePersistentDomain(forName: snapshotSuiteName) }
        let registrySuiteName = "PreloadNavigationRegistry.\(UUID().uuidString)"
        let registryDefaults = try XCTUnwrap(UserDefaults(suiteName: registrySuiteName))
        defer { registryDefaults.removePersistentDomain(forName: registrySuiteName) }
        let registry = WidgetNavigationVehicleRegistry(defaults: registryDefaults)
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(carIDs: [7, 8]),
            widgetSnapshotStore: WidgetSnapshotStore(defaults: snapshotDefaults),
            widgetTimelineReloader: RecordingWidgetTimelineReloader(),
            widgetNavigationVehicleRegistry: registry
        )

        let report = await preloader.preload(force: true)
        let identifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 8
        ))

        XCTAssertEqual(
            registry.resolve(
                serverURL: settings.serverURL,
                vehicleIdentifier: identifier
            ),
            8
        )
        XCTAssertEqual(report.requestedEndpointCount, 54)
        XCTAssertEqual(report.successfulEndpointCount, 54)
    }

    func testEmptyCarLoadDoesNotReplaceWidgetNavigationRegistry() async throws {
        let suiteName = "PreloadNavigationEmptyCars.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = WidgetNavigationVehicleRegistry(defaults: defaults)
        let settings = AppSettings(serverURL: "https://teslamate.example")
        registry.replace(serverURL: settings.serverURL, carIDs: [99])
        let previousIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 99
        ))
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(carIDs: []),
            widgetNavigationVehicleRegistry: registry
        )

        let report = await preloader.preload(force: true)

        XCTAssertEqual(
            registry.resolve(
                serverURL: settings.serverURL,
                vehicleIdentifier: previousIdentifier
            ),
            99
        )
        XCTAssertEqual(report.requestedEndpointCount, 1)
        XCTAssertEqual(report.successfulEndpointCount, 0)
    }

    func testFailedStatusPreservesAllWidgetDataAndSkipsCurrentChargeDetail() async throws {
        let suiteName = "PreloadCurrentChargeOffline.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let firstNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T10:00:00Z"))
        let secondNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T10:05:00Z"))
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )
        let successful = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(
                carIDs: [7],
                chargingCarIDs: [7],
                chargingPowerKWByCarID: [7: 72]
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { firstNow }
        )
        _ = await successful.preload(force: true)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        let beforeCurrentCharge = try XCTUnwrap(before.currentCharge)
        await reloader.reset()

        let failingClient = PreloadRecordingHTTPClient(
            carIDs: [7],
            chargingCarIDs: [7],
            failedStatusCarIDs: [7],
            chargingPowerKWByCarID: [7: 72]
        )
        let failing = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: failingClient,
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { secondNow }
        )
        let report = await failing.preload(force: true)

        let paths = await failingClient.requestedPaths
        let reloadedKinds = await reloader.kinds
        let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        let afterCurrentCharge = try XCTUnwrap(after.currentCharge)

        XCTAssertEqual(after.data, before.data)
        XCTAssertEqual(after.batteryTrend, before.batteryTrend)
        XCTAssertEqual(after.chargingTrend, before.chargingTrend)
        XCTAssertEqual(afterCurrentCharge.quality, .offline)
        XCTAssertEqual(afterCurrentCharge.batteryLevel, beforeCurrentCharge.batteryLevel)
        XCTAssertEqual(afterCurrentCharge.energyAddedKWh, beforeCurrentCharge.energyAddedKWh)
        XCTAssertEqual(afterCurrentCharge.updatedAt, beforeCurrentCharge.updatedAt)
        XCTAssertEqual(paths.filter { $0 == "/api/v1/cars/7/charges/current" }.count, 0)
        XCTAssertEqual(report.requestedEndpointCount, 28)
        XCTAssertEqual(report.successfulEndpointCount, 27)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.currentChargeKind])
    }

    func testFailedBatteryHealthOrHistoryPreservesBatteryTrendWhileOtherFieldsUpdate() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )
        let failures: [(name: String, health: Set<Int>, history: Set<Int>)] = [
            ("health", [7], []),
            ("history", [], [7])
        ]

        for failure in failures {
            let suiteName = "PreloadBatteryTrendFailure.\(failure.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = WidgetSnapshotStore(defaults: defaults)
            let reloader = RecordingWidgetTimelineReloader()
            let first = AppDataPreloader(
                settingsStore: PreloadSettingsStore(settings: settings),
                secretStore: PreloadSecretStore(),
                clientOverride: PreloadRecordingHTTPClient(),
                widgetSnapshotStore: store,
                widgetTimelineReloader: reloader,
                now: { now }
            )
            _ = await first.preload(force: true)
            let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
                serverURL: settings.serverURL,
                carID: 7
            ))
            let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
            await reloader.reset()

            let second = AppDataPreloader(
                settingsStore: PreloadSettingsStore(settings: settings),
                secretStore: PreloadSecretStore(),
                clientOverride: PreloadRecordingHTTPClient(
                    failedBatteryHealthCarIDs: failure.health,
                    failedBatteryHistoryCarIDs: failure.history,
                    lockedByCarID: [7: false]
                ),
                widgetSnapshotStore: store,
                widgetTimelineReloader: reloader,
                now: { now }
            )
            let report = await second.preload(force: true)

            let reloadedKinds = await reloader.kinds
            let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

            XCTAssertEqual(after.data.isLocked, false, failure.name)
            XCTAssertNotEqual(after.data, before.data, failure.name)
            XCTAssertEqual(after.batteryTrend, before.batteryTrend, failure.name)
            XCTAssertEqual(after.chargingTrend, before.chargingTrend, failure.name)
            XCTAssertEqual(after.currentCharge, before.currentCharge, failure.name)
            XCTAssertEqual(report.requestedEndpointCount, 28, failure.name)
            XCTAssertEqual(report.successfulEndpointCount, 27, failure.name)
            XCTAssertEqual(reloadedKinds, [WidgetConstants.carStatusKind], failure.name)
        }
    }

    func testFailedChargeHistoryPreservesChargingTrendWhileOtherFieldsUpdate() async throws {
        let suiteName = "PreloadChargingTrendFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(includesHistory: true),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await first.preload(force: true)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        XCTAssertEqual(before.chargingTrend?.sessionCount, 2)
        await reloader.reset()

        let second = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(
                includesHistory: true,
                failedChargeHistoryCarIDs: [7],
                lockedByCarID: [7: false]
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await second.preload(force: true)

        let reloadedKinds = await reloader.kinds
        let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertEqual(after.data.isLocked, false)
        XCTAssertNotEqual(after.data, before.data)
        XCTAssertEqual(after.batteryTrend, before.batteryTrend)
        XCTAssertEqual(after.chargingTrend, before.chargingTrend)
        XCTAssertEqual(after.currentCharge, before.currentCharge)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.carStatusKind])
    }

    func testWidgetPreloadReloadsOnlyChangedKinds() async throws {
        let suiteName = "PreloadTargetedReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(
                carIDs: [7],
                chargingCarIDs: [7],
                chargingPowerKWByCarID: [7: 72]
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader
        )
        _ = await first.preload(force: true)
        await reloader.reset()

        let second = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(
                carIDs: [7],
                chargingCarIDs: [7],
                chargingPowerKWByCarID: [7: 80]
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader
        )
        _ = await second.preload(force: true)

        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        XCTAssertEqual(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge?.chargerPowerKW,
            80
        )
        let reloadedKinds = await reloader.kinds
        XCTAssertEqual(reloadedKinds, [WidgetConstants.currentChargeKind])
    }

    func testWidgetPreloadReloadsOnlyCarStatusWhenOnlyDisplayDataChanges() async throws {
        let suiteName = "PreloadCarStatusTargetedReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await first.preload(force: true)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        await reloader.reset()

        let second = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(lockedByCarID: [7: false]),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await second.preload(force: true)

        let reloadedKinds = await reloader.kinds
        let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertNotEqual(after.data, before.data)
        XCTAssertEqual(after.batteryTrend, before.batteryTrend)
        XCTAssertEqual(after.chargingTrend, before.chargingTrend)
        XCTAssertEqual(after.currentCharge, before.currentCharge)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.carStatusKind])
    }

    func testWidgetPreloadReloadsOnlyBatteryTrendWhenOnlyBatteryTrendChanges() async throws {
        let suiteName = "PreloadBatteryTrendTargetedReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await first.preload(force: true)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        await reloader.reset()

        let second = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(batteryHealthPercentageByCarID: [7: 88.0]),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await second.preload(force: true)

        let reloadedKinds = await reloader.kinds
        let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertEqual(after.data, before.data)
        XCTAssertNotEqual(after.batteryTrend, before.batteryTrend)
        XCTAssertEqual(after.batteryTrend?.healthPercent, 88.0)
        XCTAssertEqual(after.chargingTrend, before.chargingTrend)
        XCTAssertEqual(after.currentCharge, before.currentCharge)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.batteryTrendKind])
    }

    func testWidgetPreloadReloadsOnlyChargingTrendWhenOnlyChargingTrendChanges() async throws {
        let suiteName = "PreloadChargingTrendTargetedReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await first.preload(force: true)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let before = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        await reloader.reset()

        let second = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(includesHistory: true),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await second.preload(force: true)

        let reloadedKinds = await reloader.kinds
        let after = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertEqual(after.data, before.data)
        XCTAssertEqual(after.batteryTrend, before.batteryTrend)
        XCTAssertNotEqual(after.chargingTrend, before.chargingTrend)
        XCTAssertEqual(after.chargingTrend?.sessionCount, 2)
        XCTAssertEqual(after.currentCharge, before.currentCharge)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.chargingTrendKind])
    }

    func testWidgetPreloadDoesNotReloadForIdenticalPayloadsOrParentTimestampOnlyChange() async throws {
        let suiteName = "PreloadNoTargetedReload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = RecordingWidgetTimelineReloader()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z"))
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: 7
        ))
        let first = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await first.preload(force: true)
        let original = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))
        await reloader.reset()

        let identical = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await identical.preload(force: true)
        let identicalKinds = await reloader.kinds
        let identicalSnapshot = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertEqual(identicalSnapshot.data, original.data)
        XCTAssertEqual(identicalSnapshot.batteryTrend, original.batteryTrend)
        XCTAssertEqual(identicalSnapshot.chargingTrend, original.chargingTrend)
        XCTAssertEqual(identicalSnapshot.currentCharge, original.currentCharge)
        XCTAssertEqual(identicalKinds, [])

        let parentTimestampOnly = WidgetVehicleSnapshot(
            id: identicalSnapshot.id,
            data: identicalSnapshot.data,
            batteryTrend: identicalSnapshot.batteryTrend,
            chargingTrend: identicalSnapshot.chargingTrend,
            currentCharge: identicalSnapshot.currentCharge,
            updatedAt: now.addingTimeInterval(-60)
        )
        store.replaceVehicleSnapshots([parentTimestampOnly], preferredIdentifier: vehicleIdentifier)
        await reloader.reset()

        let timestampRefresh = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: PreloadRecordingHTTPClient(),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            now: { now }
        )
        _ = await timestampRefresh.preload(force: true)
        let timestampKinds = await reloader.kinds
        let refreshed = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier))

        XCTAssertEqual(refreshed.data, parentTimestampOnly.data)
        XCTAssertEqual(refreshed.batteryTrend, parentTimestampOnly.batteryTrend)
        XCTAssertEqual(refreshed.chargingTrend, parentTimestampOnly.chargingTrend)
        XCTAssertEqual(refreshed.currentCharge, parentTimestampOnly.currentCharge)
        XCTAssertNotEqual(refreshed.updatedAt, parentTimestampOnly.updatedAt)
        XCTAssertEqual(timestampKinds, [])
    }

    func testDataPreloaderLoadsAndCachesEveryActivityPage() async throws {
        let client = PagedActivityPreloadHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        let report = await preloader.preload(force: true)
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(report.didRun)
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/activities?page=1&show=200"))
        XCTAssertTrue(requestedPaths.contains("/api/v1/cars/7/activities?page=2&show=200"))
        XCTAssertEqual(snapshot?.state.items.map(\.stableID), ["drive-3", "charge-2", "park-1"])
        XCTAssertEqual(snapshot?.state.loadedPageCount, 2)
        XCTAssertTrue(snapshot?.state.historyFullyLoaded == true)
        XCTAssertFalse(snapshot?.state.hasMore == true)
    }

    func testDataPreloaderOnlyRefreshesNewestActivityPagesAfterHistoryIsCached() async {
        let client = PagedActivityPreloadHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        _ = await preloader.preload(force: true)
        _ = await preloader.preload(force: true)
        let activityRequests = await client.requestedPaths.filter { $0.contains("/activities?") }

        XCTAssertEqual(activityRequests, [
            "/api/v1/cars/7/activities?page=1&show=200",
            "/api/v1/cars/7/activities?page=2&show=200",
            "/api/v1/cars/7/activities?page=1&show=200"
        ])
    }

    func testDataPreloaderPersistsActivityProgressAfterEveryPage() async {
        let client = PausedActivityPreloadHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        let preloader = AppDataPreloader(
            settingsStore: PreloadSettingsStore(settings: settings),
            secretStore: PreloadSecretStore(),
            clientOverride: client,
            activitiesCache: cache
        )

        let preload = Task { await preloader.preload(force: true) }
        await client.waitUntilSecondPageRequested()
        let partial = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())
        await client.releaseSecondPage()
        _ = await preload.value

        XCTAssertEqual(partial?.state.items.map(\.stableID), ["drive-2"])
        XCTAssertEqual(partial?.state.loadedPageCount, 1)
        XCTAssertTrue(partial?.state.hasMore == true)
        XCTAssertFalse(partial?.state.historyFullyLoaded == true)
    }

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
        let indexCounter = BackgroundRefreshCounter()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { false },
            rebuildSmartActivities: { _ in
                await indexCounter.increment()
                return true
            }
        )

        let report = await runner.run()
        let indexCount = await indexCounter.value

        XCTAssertFalse(report.isSuccessful)
        XCTAssertFalse(report.vehicleStatusRefreshed)
        XCTAssertFalse(report.smartActivitiesIndexed)
        XCTAssertEqual(indexCount, 0)
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

    func testHistorySyncStartsWithoutWaitingForPageWarmup() async {
        let gate = BackgroundWorkGate()
        let history = ObservableBackgroundHistoryRunner(gate: gate)
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: history,
            refreshVehicleStatus: {
                await gate.waitForRelease()
                return true
            }
        )

        let task = Task { await runner.run() }
        await gate.waitUntilStarted()
        await history.waitUntilStarted()
        let historyStartedDuringWarmup = await history.hasStarted
        XCTAssertTrue(historyStartedDuringWarmup)

        await gate.release()
        _ = await task.value
    }

    func testAppDataSyncCoordinatorKeepsOneIndependentFullSyncRunning() async {
        let gate = BackgroundWorkGate()
        let worker = GatedBackgroundRefreshWorker(gate: gate)
        let coordinator = AppDataSyncCoordinator(workRunner: worker)

        let firstStarted = await coordinator.start()
        let duplicateStarted = await coordinator.start()
        await gate.waitUntilStarted()
        let runningBeforeRelease = await coordinator.isRunning

        XCTAssertTrue(firstStarted)
        XCTAssertFalse(duplicateStarted)
        XCTAssertTrue(runningBeforeRelease)

        await gate.release()
        let report = await coordinator.waitUntilIdle()
        let runCount = await worker.runCount
        let isRunning = await coordinator.isRunning

        XCTAssertEqual(report?.vehicleStatusRefreshed, true)
        XCTAssertEqual(runCount, 1)
        XCTAssertFalse(isRunning)
    }

    func testBecomingActiveStartsFullSyncWhilePagesReadCachedData() async {
        let gate = BackgroundWorkGate()
        let worker = GatedBackgroundRefreshWorker(gate: gate)
        let coordinator = AppDataSyncCoordinator(workRunner: worker)
        let controller = await MainActor.run {
            AppDataSyncLifecycleController(coordinator: coordinator)
        }

        await controller.appDidBecomeActive()
        for _ in 0 ..< 50 where await worker.runCount == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }

        let isRunning = await coordinator.isRunning
        let runCount = await worker.runCount

        XCTAssertTrue(isRunning)
        XCTAssertEqual(runCount, 1)

        await gate.release()
        _ = await coordinator.waitUntilIdle()
    }

    func testCompletingFullSyncPublishesNewCacheRevision() async {
        let gate = BackgroundWorkGate()
        let worker = GatedBackgroundRefreshWorker(gate: gate)
        let coordinator = AppDataSyncCoordinator(workRunner: worker)
        let controller = await MainActor.run {
            AppDataSyncLifecycleController(coordinator: coordinator)
        }

        await controller.appDidBecomeActive()
        let initialRevision = await MainActor.run { controller.cacheRevision }
        XCTAssertEqual(initialRevision, 0)

        await gate.release()
        for _ in 0 ..< 100 {
            let revision = await MainActor.run { controller.cacheRevision }
            if revision == 1 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }

        let revision = await MainActor.run { controller.cacheRevision }
        XCTAssertEqual(revision, 1)
    }

    func testServerConfigurationChangeCancelsOldCompletionAndStartsFreshSync() async {
        let worker = ServerSwitchBackgroundRefreshWorker()
        let coordinator = AppDataSyncCoordinator(workRunner: worker)
        let completions = BackgroundCompletionCounter()
        let controller = await MainActor.run {
            AppDataSyncLifecycleController(
                coordinator: coordinator,
                didCompleteSync: { _ in await completions.increment() }
            )
        }

        await controller.appDidBecomeActive()
        await worker.waitUntilFirstRunStarts()
        await controller.serverConfigurationDidChange()

        for _ in 0 ..< 100 where await completions.value < 1 {
            try? await Task.sleep(for: .milliseconds(2))
        }

        let runCount = await worker.runCount
        let completionCount = await completions.value
        let revision = await MainActor.run { controller.cacheRevision }
        XCTAssertEqual(runCount, 2)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(revision, 2)
    }

    func testSuspendedLifecycleDoesNotRepublishPreviousSyncCompletion() async {
        let gate = BackgroundWorkGate()
        let worker = GatedBackgroundRefreshWorker(gate: gate)
        let coordinator = AppDataSyncCoordinator(workRunner: worker)

        let didStart = await coordinator.start()
        XCTAssertTrue(didStart)
        await gate.waitUntilStarted()
        await gate.release()
        _ = await coordinator.waitUntilIdle()
        await coordinator.suspendAndWait()

        let completions = BackgroundCompletionCounter()
        let controller = await MainActor.run {
            AppDataSyncLifecycleController(
                coordinator: coordinator,
                didCompleteSync: { _ in await completions.increment() }
            )
        }

        await controller.appDidBecomeActive()
        try? await Task.sleep(for: .milliseconds(20))

        let completionCount = await completions.value
        let revision = await MainActor.run { controller.cacheRevision }
        let runCount = await worker.runCount
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(revision, 0)
        XCTAssertEqual(runCount, 1)
    }

    func testBackgroundSyncPublishesRevisionAndCompletionOnce() async {
        let gate = BackgroundWorkGate()
        let worker = GatedBackgroundRefreshWorker(gate: gate)
        let coordinator = AppDataSyncCoordinator(workRunner: worker)
        let backgroundTasks = await MainActor.run { TestBackgroundTaskManager() }
        let completions = BackgroundCompletionCounter()
        let controller = await MainActor.run {
            AppDataSyncLifecycleController(
                coordinator: coordinator,
                backgroundTaskManager: backgroundTasks,
                didCompleteSync: { _ in await completions.increment() }
            )
        }

        await MainActor.run {
            controller.appDidEnterBackground()
            controller.appDidEnterBackground()
        }
        await gate.waitUntilStarted()
        let beginCount = await MainActor.run { backgroundTasks.beginCount }
        XCTAssertEqual(beginCount, 1)

        await gate.release()
        for _ in 0 ..< 100 {
            let revision = await MainActor.run { controller.cacheRevision }
            if revision == 1, await completions.value == 1 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }

        let revision = await MainActor.run { controller.cacheRevision }
        let completionCount = await completions.value
        let endCount = await MainActor.run { backgroundTasks.endCount }
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(endCount, 1)
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

        let partialReport = await preloader.preload(force: true)
        let partial = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertFalse(partialReport.activitiesRefreshSucceeded)
        XCTAssertFalse(partialReport.canIndexSmartActivities)
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

    func testDataPreloaderReplacesNonemptyCompleteCacheWithTrustedEmptyHistory() async {
        let client = EmptyActivityHistoryHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        var completeState = ActivitiesState()
        completeState.items = [
            TeslaMateActivity(id: 1, type: "charge", startDate: "2026-07-01T00:00:00Z")
        ]
        completeState.loadedPageCount = 1
        completeState.historyFullyLoaded = true
        completeState.historyContinuityAnchorID = "charge-1"
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
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertTrue(snapshot?.state.items.isEmpty == true)
        XCTAssertTrue(snapshot?.state.historyFullyLoaded == true)
        XCTAssertFalse(snapshot?.state.hasMore == true)
        XCTAssertNil(snapshot?.state.historyContinuityAnchorID)
    }

    func testDataPreloaderReplacesDeletedCachedActivitiesWithAuthoritativeChangedHistory() async {
        let client = ChangedActivityHistoryHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        var completeState = ActivitiesState()
        completeState.items = [
            TeslaMateActivity(id: 1, type: "charge", startDate: "2026-07-01T00:00:00Z"),
            TeslaMateActivity(id: 2, type: "drive", startDate: "2026-07-02T00:00:00Z")
        ]
        completeState.loadedPageCount = 1
        completeState.historyFullyLoaded = true
        completeState.historyContinuityAnchorID = "drive-2"
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
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertEqual(snapshot?.state.items.map(\.stableID), ["drive-3"])
        XCTAssertTrue(snapshot?.state.historyFullyLoaded == true)
        XCTAssertFalse(snapshot?.state.hasMore == true)
        XCTAssertEqual(snapshot?.state.historyContinuityAnchorID, "drive-3")
    }

    func testDataPreloaderRemovesDeletedCachedActivityWhenReliableLastPageContainsAnchor() async {
        let client = AnchoredAuthoritativeActivityHistoryHTTPClient()
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        var completeState = ActivitiesState()
        completeState.items = [
            TeslaMateActivity(id: 2, type: "drive", startDate: "2026-07-02T00:00:00Z"),
            TeslaMateActivity(id: 1, type: "charge", startDate: "2026-07-01T00:00:00Z")
        ]
        completeState.loadedPageCount = 1
        completeState.historyFullyLoaded = true
        completeState.historyContinuityAnchorID = "drive-2"
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
        let snapshot = await cache.load(serverURL: settings.serverURL, carId: 7, now: Date())

        XCTAssertEqual(snapshot?.state.items.map(\.stableID), ["drive-2"])
        XCTAssertTrue(snapshot?.state.historyFullyLoaded == true)
        XCTAssertFalse(snapshot?.state.hasMore == true)
        XCTAssertEqual(snapshot?.state.historyContinuityAnchorID, "drive-2")
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

private actor ObservableBackgroundHistoryRunner: HistorySyncRunning {
    private let gate: BackgroundWorkGate
    private(set) var hasStarted = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    init(gate: BackgroundWorkGate) {
        self.gate = gate
    }

    func run() async -> HistorySyncReport {
        hasStarted = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }
}

private actor BackgroundRefreshCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor BackgroundWorkGate {
    private var started = false
    private var released = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRelease() async {
        started = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor GatedBackgroundRefreshWorker: BackgroundRefreshWorkRunning {
    private let gate: BackgroundWorkGate
    private(set) var runCount = 0

    init(gate: BackgroundWorkGate) {
        self.gate = gate
    }

    func run() async -> BackgroundRefreshReport {
        runCount += 1
        await gate.waitForRelease()
        return BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: []),
            vehicleStatusRefreshed: true
        )
    }
}

private actor ServerSwitchBackgroundRefreshWorker: BackgroundRefreshWorkRunning {
    private(set) var runCount = 0
    private var firstRunStarted = false
    private var firstRunWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async -> BackgroundRefreshReport {
        runCount += 1
        if runCount == 1 {
            firstRunStarted = true
            firstRunWaiters.forEach { $0.resume() }
            firstRunWaiters.removeAll()
            try? await Task.sleep(for: .seconds(60))
        }
        return BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(
                attemptedCarIDs: [1],
                completedCarIDs: [1],
                failedCarIDs: []
            ),
            vehicleStatusRefreshed: true
        )
    }

    func waitUntilFirstRunStarts() async {
        guard !firstRunStarted else { return }
        await withCheckedContinuation { firstRunWaiters.append($0) }
    }
}

private actor RecordingWidgetTimelineReloader: WidgetTimelineReloading {
    private(set) var kinds: [String] = []

    func reloadTimelines(ofKind kind: String) async {
        kinds.append(kind)
    }

    func reset() {
        kinds.removeAll()
    }
}

private actor BackgroundRecordingLiveActivityManager: ChargeLiveActivityManaging {
    enum Call: Equatable, Sendable {
        case startOrUpdate(carId: Int)
        case updateExisting(carId: Int)
        case end(carId: Int, vehicleIdentifier: String?)
    }

    private var calls: [Call] = []
    private var existingSnapshots: [ChargeLiveActivitySnapshot] = []

    func update(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.startOrUpdate(carId: carId))
    }

    func updateExisting(carId: Int, snapshot: ChargeLiveActivitySnapshot) async {
        calls.append(.updateExisting(carId: carId))
        existingSnapshots.append(snapshot)
    }

    func end(carId: Int) async {
        calls.append(.end(carId: carId, vehicleIdentifier: nil))
    }

    func end(carId: Int, vehicleIdentifier: String?) async {
        calls.append(.end(carId: carId, vehicleIdentifier: vehicleIdentifier))
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func recordedExistingSnapshots() -> [ChargeLiveActivitySnapshot] {
        existingSnapshots
    }
}

private actor PreloadRecordingHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private let carIDs: [Int]
    private let includesHistory: Bool
    private let placePageCount: Int
    private let chargingCarIDs: Set<Int>
    private let failedStatusCarIDs: Set<Int>
    private let chargingPowerKWByCarID: [Int: Int]
    private let failedBatteryHealthCarIDs: Set<Int>
    private let failedBatteryHistoryCarIDs: Set<Int>
    private let failedChargeHistoryCarIDs: Set<Int>
    private let lockedByCarID: [Int: Bool]
    private let batteryHealthPercentageByCarID: [Int: Double]

    init(
        carIDs: [Int] = [7],
        includesHistory: Bool = false,
        placePageCount: Int = 1,
        chargingCarIDs: Set<Int> = [],
        failedStatusCarIDs: Set<Int> = [],
        chargingPowerKWByCarID: [Int: Int] = [:],
        failedBatteryHealthCarIDs: Set<Int> = [],
        failedBatteryHistoryCarIDs: Set<Int> = [],
        failedChargeHistoryCarIDs: Set<Int> = [],
        lockedByCarID: [Int: Bool] = [:],
        batteryHealthPercentageByCarID: [Int: Double] = [:]
    ) {
        self.carIDs = carIDs
        self.includesHistory = includesHistory
        self.placePageCount = placePageCount
        self.chargingCarIDs = chargingCarIDs
        self.failedStatusCarIDs = failedStatusCarIDs
        self.chargingPowerKWByCarID = chargingPowerKWByCarID
        self.failedBatteryHealthCarIDs = failedBatteryHealthCarIDs
        self.failedBatteryHistoryCarIDs = failedBatteryHistoryCarIDs
        self.failedChargeHistoryCarIDs = failedChargeHistoryCarIDs
        self.lockedByCarID = lockedByCarID
        self.batteryHealthPercentageByCarID = batteryHealthPercentageByCarID
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            let cars = carIDs.map { #"{"car_id":\#($0),"name":"Test car \#($0)"}"# }.joined(separator: ",")
            body = #"{"data":{"cars":[\#(cars)]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/status"),
                  let carID = url.path.split(separator: "/").dropLast().last.flatMap({ Int($0) }) {
            let locked = lockedByCarID[carID] ?? true
            if failedStatusCarIDs.contains(carID) {
                body = #"{}"#
                statusCode = 503
            } else if chargingCarIDs.contains(carID) {
                let chargerPower = chargingPowerKWByCarID[carID] ?? 72
                body = #"{"data":{"status":{"display_name":"Test car \#(carID)","battery_details":{"battery_level":\#(60 + carID),"rated_battery_range":320},"car_status":{"locked":\#(locked)},"charging_details":{"charging_state":"Charging","charge_limit_soc":80,"charger_power":\#(chargerPower),"charge_energy_added":12.5,"time_to_full_charge":1.5}},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}}"#
                statusCode = 200
            } else {
                body = #"{"data":{"status":{"display_name":"Test car \#(carID)","battery_details":{"battery_level":\#(60 + carID),"rated_battery_range":320},"car_status":{"locked":\#(locked)},"charging_details":{"charging_state":"Disconnected"}},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}}"#
                statusCode = 200
            }
        } else if url.path.hasSuffix("/battery-health/history"),
                  let carID = url.path.split(separator: "/").dropLast(2).last.flatMap({ Int($0) }) {
            if failedBatteryHistoryCarIDs.contains(carID) {
                body = #"{}"#
                statusCode = 503
            } else {
                body = #"{"data":{"charts":{"capacity":[{"date":"2026-01-01","odometer":10000,"capacity":75.0},{"date":"2026-06-01","odometer":20000,"capacity":70.0}],"capacity_median":[],"range":[]},"efficiency":{"value":150,"ready":true,"qualifying_charge_count":3,"required_charge_count":2}}}"#
                statusCode = 200
            }
        } else if url.path.hasSuffix("/battery-health"),
                  let carID = url.path.split(separator: "/").dropLast().last.flatMap({ Int($0) }) {
            if failedBatteryHealthCarIDs.contains(carID) {
                body = #"{}"#
                statusCode = 503
            } else {
                let healthPercentage = batteryHealthPercentageByCarID[carID] ?? 93.3
                body = #"{"data":{"battery_health":{"max_capacity":75.0,"current_capacity":70.0,"battery_health_percentage":\#(healthPercentage)}}}"#
                statusCode = 200
            }
        } else if url.path.hasSuffix("/drives") {
            body = includesHistory
                ? #"{"data":{"drives":[{"drive_id":107,"start_date":"2026-07-15T08:00:00Z"},{"drive_id":106,"start_date":"2026-07-14T08:00:00Z"}]}}"#
                : #"{"data":{"drives":[]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/charges/current"),
                  let carID = url.path.split(separator: "/").dropLast(2).last.flatMap({ Int($0) }) {
            body = #"{"data":{"car":{"car_id":\#(carID),"car_name":"Test car \#(carID)"},"charge":{"charge_id":\#(9000 + carID),"charge_energy_added":18.4,"battery_details":{"start_battery_level":40,"current_battery_level":67},"charge_points":[],"is_charging":true}}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/charges"),
                  let carID = url.path.split(separator: "/").dropLast().last.flatMap({ Int($0) }) {
            if failedChargeHistoryCarIDs.contains(carID) {
                body = #"{}"#
                statusCode = 503
            } else {
                body = includesHistory
                    ? #"{"data":{"charges":[{"charge_id":207,"start_date":"2026-07-15T20:00:00Z"},{"charge_id":206,"start_date":"2026-07-14T20:00:00Z"}]}}"#
                    : #"{"data":{"charges":[]}}"#
                statusCode = 200
            }
        } else if url.path.hasSuffix("/drives/107") || url.path.hasSuffix("/drives/106") {
            let driveID = url.path.hasSuffix("107") ? 107 : 106
            body = #"{"data":{"drive":{"drive_id":\#(driveID),"positions":[]}}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/charges/207") || url.path.hasSuffix("/charges/206") {
            let chargeID = url.path.hasSuffix("207") ? 207 : 206
            body = #"{"data":{"charge":{"charge_id":\#(chargeID),"charge_points":[]}}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/places") {
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
            body = #"{"data":[],"pagination":{"page":\#(page),"limit":100,"totalPages":\#(placePageCount),"totalRecords":0}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/top-drain-locations") {
            body = #"{"locations":[{"address":"Home","latitude":28.2,"longitude":112.9}]}"#
            statusCode = 200
        } else if url.path.hasSuffix("/standby-drain") {
            body = #"{"data":{"latitude":28.2,"longitude":112.9}}"#
            statusCode = 200
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

private actor ChangedActivityHistoryHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities") {
            body = #"{"data":[{"id":3,"type":"drive","startDate":"2026-07-03T00:00:00Z"}],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":1}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor AnchoredAuthoritativeActivityHistoryHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities") {
            body = #"{"data":[{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":1}}"#
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

private actor ActivityFreshnessHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private let carIDs: [Int]
    private let failedActivityCarIDs: Set<Int>

    init(carIDs: [Int] = [7], failedActivityCarIDs: Set<Int> = []) {
        self.carIDs = carIDs
        self.failedActivityCarIDs = failedActivityCarIDs
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let body: String
        if url.path == "/api/v1/cars" {
            let cars = carIDs.map { #"{"car_id":\#($0),"name":"Test car \#($0)"}"# }
                .joined(separator: ",")
            body = #"{"data":{"cars":[\#(cars)]}}"#
        } else if url.path.hasSuffix("/activities"),
                  let carID = url.path.split(separator: "/").dropLast().last.flatMap({ Int($0) }) {
            if failedActivityCarIDs.contains(carID) {
                throw APIError.httpStatus(503)
            }
            body = #"{"data":[],"pagination":{"page":1,"limit":200,"totalPages":1,"totalRecords":0}}"#
        } else if url.path.hasSuffix("/status"),
                  let carID = url.path.split(separator: "/").dropLast().last.flatMap({ Int($0) }) {
            body = #"{"data":{"status":{"display_name":"Test car \#(carID)","battery_details":{"battery_level":60},"car_status":{"locked":true},"charging_details":{"charging_state":"Disconnected"}}}}"#
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

private actor PagedActivityPreloadHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities"), page == 1 {
            body = #"{"data":[{"id":3,"type":"drive","startDate":"2026-07-03T00:00:00Z"},{"id":2,"type":"charge","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"page":1,"limit":2,"totalPages":2,"totalRecords":3}}"#
        } else if url.path.hasSuffix("/activities"), page == 2 {
            body = #"{"data":[{"id":1,"type":"park","startDate":"2026-07-01T00:00:00Z"}],"pagination":{"page":2,"limit":2,"totalPages":2,"totalRecords":3}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor PausedActivityPreloadHTTPClient: HTTPClient {
    private var secondPageRequested = false
    private var secondPageReleased = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if url.path.hasSuffix("/activities"), page == 1 {
            body = #"{"data":[{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"page":1,"limit":1,"totalPages":2,"totalRecords":2}}"#
        } else if url.path.hasSuffix("/activities"), page == 2 {
            secondPageRequested = true
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
            if !secondPageReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
            body = #"{"data":[{"id":1,"type":"charge","startDate":"2026-07-01T00:00:00Z"}],"pagination":{"page":2,"limit":1,"totalPages":2,"totalRecords":2}}"#
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }

    func waitUntilSecondPageRequested() async {
        guard !secondPageRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseSecondPage() {
        secondPageReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor PreloadSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private struct PreloadSecretStore: SecretStoring {
    func get(_ key: String) async throws -> String? { nil }
    func set(_ value: String, for key: String) async throws {}
    func remove(_ key: String) async throws {}
}

@MainActor
private final class TestBackgroundTaskManager: AppBackgroundTaskManaging {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var nextIdentifier = 1
    private var expirationHandlers: [UIBackgroundTaskIdentifier: @Sendable () -> Void] = [:]

    func begin(
        name _: String,
        expirationHandler: @escaping @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        beginCount += 1
        let identifier = UIBackgroundTaskIdentifier(rawValue: nextIdentifier)
        nextIdentifier += 1
        expirationHandlers[identifier] = expirationHandler
        return identifier
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        endCount += 1
        expirationHandlers[identifier] = nil
    }
}

private actor BackgroundCompletionCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
