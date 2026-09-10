import XCTest
@testable import MateDriveApp

@MainActor
final class DrivesViewModelTests: XCTestCase {
    func testDriveFiltersUseAppLanguageForDisplayTitles() {
        XCTAssertEqual(DriveDateFilter.allTime.title(language: .chinese), "全部")
        XCTAssertEqual(DriveDateFilter.today.title(language: .chinese), "今天")
        XCTAssertEqual(DriveDateFilter.lastYear.title(language: .chinese), "一年")
        XCTAssertEqual(DriveDistanceFilter.all.title(language: .chinese), "全部")
        XCTAssertEqual(DriveDistanceFilter.commute.title(language: .chinese), "通勤")
        XCTAssertEqual(DriveDistanceFilter.dayTrip.title(language: .chinese), "短途")
        XCTAssertEqual(DriveDistanceFilter.roadTrip.title(language: .chinese), "长途")

        XCTAssertEqual(DriveDateFilter.allTime.title(language: .english), "All Time")
        XCTAssertEqual(DriveDistanceFilter.roadTrip.title(language: .english), "Road Trip")
    }

    func testDrivesViewModelHidesShortDrivesWhenSettingIsOff() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 0.9, durationMin: 10),
            .fixture(driveId: 2, distance: 14.0, durationMin: 20)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: false,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2])
        XCTAssertEqual(viewModel.state.summary.totalDrives, 2)
    }

    func testDistanceFilterUsesExpectedDriveCategories() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 9.9, durationMin: 10),
            .fixture(driveId: 2, distance: 10.0, durationMin: 15),
            .fixture(driveId: 3, distance: 100.0, durationMin: 60)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)
        viewModel.setDistanceFilter(.dayTrip)

        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2])
        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 10.0)

        viewModel.setDistanceFilter(.roadTrip)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [3])
    }

    func testIntelligenceSuggestsMorningCommuteAfterFourMatchingWeekdayDrives() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let route = syntheticRouteFingerprint()
        let items = (0..<4).map { index in
            DriveSummaryItem.fixture(
                driveId: index + 1,
                distance: 12,
                durationMin: 30,
                startDate: "2026-07-0\(6 + index)T08:10:00Z",
                efficiency: 180 + Double(index),
                routeFingerprint: route
            )
        }

        let results = DriveIntelligenceEngine.analyze(
            items: items,
            carId: 1,
            routeLabels: [],
            annotations: [:],
            geofences: [],
            calendar: calendar
        )

        XCTAssertEqual(results[4]?.suggestion?.name, "上班通勤")
        XCTAssertEqual(results[4]?.suggestion?.matchingDriveCount, 4)
        XCTAssertNil(results[4]?.confirmedLabel)
    }

    func testConfirmedRouteUsesPreviousEightMedianAndMarksNewPersonalBest() {
        let route = syntheticRouteFingerprint()
        let efficiencies = [210.0, 205, 200, 195, 190, 185, 180, 175, 160]
        let items = efficiencies.enumerated().map { index, efficiency in
            DriveSummaryItem.fixture(
                driveId: index + 1,
                distance: 12,
                durationMin: 30,
                startDate: String(format: "2026-07-%02dT08:10:00Z", index + 1),
                efficiency: efficiency,
                routeFingerprint: route
            )
        }
        let rule = DriveRouteLabelRule(
            carId: 1,
            name: "上班通勤",
            direction: .outbound,
            typicalDistanceKm: 12,
            fingerprint: route
        )

        let result = DriveIntelligenceEngine.analyze(
            items: items,
            carId: 1,
            routeLabels: [rule],
            annotations: [:],
            geofences: []
        )[9]

        XCTAssertEqual(result?.confirmedLabel?.id, rule.id)
        XCTAssertEqual(result?.benchmark.benchmarkEfficiency ?? 0, 192.5, accuracy: 0.001)
        XCTAssertEqual(result?.benchmark.sampleCount, 8)
        XCTAssertEqual(result?.benchmark.rank, 1)
        XCTAssertEqual(result?.benchmark.accent, .personalBest)
        XCTAssertEqual(result?.benchmark.previousBestEfficiency, 175)
    }

    func testBenchmarkExcludesIncompleteAndDistanceMismatchedDrives() {
        let route = syntheticRouteFingerprint()
        let rule = DriveRouteLabelRule(carId: 1, name: "健身", typicalDistanceKm: 10, fingerprint: route)
        let items = [
            DriveSummaryItem.fixture(driveId: 1, distance: 10, durationMin: 20, startDate: "2026-07-01T18:00:00Z", efficiency: 180, routeFingerprint: route),
            DriveSummaryItem.fixture(driveId: 2, distance: 13, durationMin: 20, startDate: "2026-07-02T18:00:00Z", efficiency: 170, routeFingerprint: route),
            DriveSummaryItem.fixture(driveId: 3, distance: 10, durationMin: 20, startDate: "2026-07-03T18:00:00Z", efficiency: nil, routeFingerprint: route),
            DriveSummaryItem.fixture(driveId: 4, distance: 10, durationMin: 20, startDate: "2026-07-04T18:00:00Z", efficiency: 160, routeFingerprint: route)
        ]

        let result = DriveIntelligenceEngine.analyze(
            items: items,
            carId: 1,
            routeLabels: [rule],
            annotations: [:],
            geofences: []
        )[4]

        XCTAssertEqual(result?.benchmark.sampleCount, 1)
        XCTAssertEqual(result?.benchmark.samplesNeeded, 3)
        XCTAssertNil(result?.benchmark.benchmarkEfficiency)
    }

    func testSummaryCalculatesDistanceDurationSpeedAndEfficiency() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 20, durationMin: 30, speedMax: 80, efficiency: 180, efficiencySource: .api),
            .fixture(driveId: 2, distance: 40, durationMin: 60, speedMax: 100, efficiency: 220, efficiencySource: .powerSamples)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 60)
        XCTAssertEqual(viewModel.state.summary.totalDurationMin, 90)
        XCTAssertEqual(viewModel.state.summary.maxSpeedKmh, 100)
        XCTAssertEqual(viewModel.state.summary.avgEfficiencyWhKm, 200)
        XCTAssertEqual(viewModel.state.summary.reconstructedEfficiencyCount, 1)
    }

    func testHistorySummaryAndChartIncludeRatedRangeUse() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(
                driveId: 1,
                distance: 20,
                durationMin: 30,
                startRatedRangeKm: 380,
                endRatedRangeKm: 342
            ),
            .fixture(
                driveId: 2,
                distance: 10,
                durationMin: 15,
                startRatedRangeKm: 342,
                endRatedRangeKm: 330
            )
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalRatedRangeDropKm, 50)
        XCTAssertEqual(viewModel.state.summary.ratedRangeRecordCount, 2)
        XCTAssertTrue(viewModel.state.summary.ratedRangeIsComplete)
        XCTAssertEqual(viewModel.state.rows.first?.ratedRangeDropKm, 38)
        XCTAssertEqual(viewModel.state.chartData.first?.totalRatedRangeDrop, 50)
    }

    func testAPISummaryProviderEnrichesZeroEnergyFromDriveDetails() async throws {
        let provider = APIDriveSummaryProvider(api: MissingEnergyDriveAPI())

        let summaries = try await provider.driveSummaries(carId: 1).successValue()
        let items = await provider.enrichDriveSummaries(summaries, carId: 1)
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(try XCTUnwrap(item.energyConsumedNet), 0.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(item.efficiency), 100, accuracy: 0.1)
        XCTAssertEqual(item.efficiencySource, .powerSamples)
    }

    func testViewModelShowsRowsBeforeBackgroundEnergyEnrichmentCompletes() async throws {
        let gate = DriveEnrichmentGate()
        let provider = DeferredDriveEnrichmentProvider(gate: gate)
        let viewModel = DrivesViewModel(
            store: provider,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [10])
        XCTAssertNil(viewModel.state.rows.first?.efficiency)

        await gate.waitUntilStarted()
        await gate.release()
        for _ in 0..<100 where viewModel.state.rows.first?.efficiency == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state.rows.first?.efficiency, 100)
        XCTAssertEqual(viewModel.state.rows.first?.efficiencySource, .powerSamples)
    }

    func testViewModelShowsRowsWithoutWaitingForSlowUnitStatus() async {
        let gate = DriveEnrichmentGate()
        let provider = DeferredDriveUnitsProvider(gate: gate)
        let viewModel = DrivesViewModel(
            store: provider,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        let loadTask = Task { await viewModel.load(carId: 1) }
        await gate.waitUntilStarted()
        for _ in 0..<20 where viewModel.state.rows.isEmpty {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [10])

        await gate.release()
        await loadTask.value
        XCTAssertEqual(viewModel.state.units, .metric)
    }

    func testViewModelShowsPersistentCacheBeforeFullHistoryRequestCompletes() async {
        let gate = DriveEnrichmentGate()
        let provider = CacheFirstDriveSummaryProvider(gate: gate)
        let viewModel = DrivesViewModel(
            store: provider,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        let loadTask = Task { await viewModel.load(carId: 1) }
        await gate.waitUntilStarted()
        for _ in 0..<20 where viewModel.state.rows.isEmpty {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.isUsingCachedData)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [41])

        await gate.release()
        await loadTask.value

        XCTAssertFalse(viewModel.state.isUsingCachedData)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [42])
    }

    func testOpeningDrivePrimesScopedDetailSnapshotFromVisibleSummary() async throws {
        let item = DriveSummaryItem.fixture(
            driveId: 42,
            distance: 21,
            durationMin: 30,
            efficiency: 180
        )
        let viewModel = DrivesViewModel(
            store: FakeDriveSummaryProvider(items: [item]),
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )
        let cache = DriveDetailStateCache()
        let key = DriveDetailCacheKey(
            serverURL: "https://teslamate.example",
            carId: 1,
            driveId: 42
        )
        await viewModel.load(carId: 1)

        viewModel.primeDetailSnapshot(driveId: 42, cacheKey: key, stateCache: cache)

        let snapshot = try XCTUnwrap(cache.state(for: key))
        XCTAssertFalse(snapshot.isLoading)
        XCTAssertTrue(snapshot.isShowingSummary)
        XCTAssertEqual(snapshot.driveDetail?.driveId, 42)
        XCTAssertEqual(snapshot.driveDetail?.distance, 21)
        XCTAssertEqual(snapshot.stats?.efficiency, 180)
    }

    func testAPISummaryProviderFallsBackToVehicleScopedCacheWhenAPIIsOffline() async throws {
        let cached = DriveSummaryItem(
            driveId: 42,
            carId: 1,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: 21,
            durationMin: 30,
            startAddress: nil,
            endAddress: nil,
            speedMax: nil,
            speedAvg: nil,
            energyConsumedNet: 4.2,
            efficiency: 200,
            efficiencySource: .api,
            outsideTempAvg: nil
        )
        let provider = APIDriveSummaryProvider(
            api: OfflineDriveAPI(),
            cache: FakeDriveSummaryCache(items: [cached])
        )

        let result = await provider.driveSummaries(carId: 1)
        let items = try result.successValue()

        XCTAssertEqual(items.map(\.driveId), [42])
        XCTAssertEqual(items.first?.energyConsumedNet, 4.2)
        XCTAssertEqual(items.first?.isCached, true)

        let viewModel = DrivesViewModel(store: provider, showShortEntries: true, initialState: DrivesState(dateFilter: .allTime))
        await viewModel.load(carId: 1)
        XCTAssertTrue(viewModel.state.isUsingCachedData)
    }

    func testSummaryItemMarksServerEfficiencyAsDirectData() {
        let item = DriveSummaryItem(
            data: DriveData(driveId: 1, distance: 10, durationMin: 20, consumptionNet: 168),
            carId: 1
        )

        XCTAssertEqual(item.efficiency, 168)
        XCTAssertEqual(item.efficiencySource, .api)
    }

    func testDriveSummaryPreservesMissingDistanceAndDurationAndReportsCoverage() async {
        let items = [
            DriveSummaryItem(data: DriveData(driveId: 1, startDate: "2026-07-01T08:00:00Z", distance: 20, durationMin: 30), carId: 1),
            DriveSummaryItem(data: DriveData(driveId: 2, startDate: "2026-07-02T08:00:00Z", distance: nil, durationMin: nil), carId: 1)
        ]
        let viewModel = DrivesViewModel(
            store: FakeDriveSummaryProvider(items: items),
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertNil(items[1].distance)
        XCTAssertNil(items[1].durationMin)
        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 20)
        XCTAssertEqual(viewModel.state.summary.distanceRecordCount, 1)
        XCTAssertFalse(viewModel.state.summary.distanceIsComplete)
        XCTAssertEqual(viewModel.state.summary.totalDurationMin, 30)
        XCTAssertEqual(viewModel.state.summary.durationRecordCount, 1)
        XCTAssertFalse(viewModel.state.summary.durationIsComplete)
        XCTAssertEqual(DrivesPresentation.distanceText(nil, isComplete: false, units: .metric), "--")
        XCTAssertEqual(DrivesPresentation.distanceText(20, isComplete: false, units: .metric), "≥20.0 km")
        XCTAssertEqual(DrivesPresentation.durationText(30, isComplete: false, language: .chinese), "≥30分钟")
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2, 1])

        viewModel.setDistanceFilter(.commute)
        XCTAssertTrue(viewModel.state.rows.isEmpty)
    }
}

private struct MissingEnergyDriveAPI: DriveAPIProviding {
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        guard (page ?? 1) == 1 else { return .success([]) }
        return .success([
            DriveData(
                driveId: 10,
                carId: 1,
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T08:00:20Z",
                distance: 0.5,
                durationMin: 1,
                energyConsumedNet: 0,
                consumptionNet: 0
            )
        ])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .success(DriveDetail(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:00:20Z",
            odometerDetails: DriveOdometerDetails(distance: 0.5),
            durationMin: 1,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:10Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:20Z", power: -18)
            ]
        ))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }
}

private struct OfflineDriveAPI: DriveAPIProviding {
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .failure(.network("offline"))
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .failure(.network("offline"))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .failure(.network("offline"))
    }
}

private struct FakeDriveSummaryCache: DriveSummaryCaching {
    let items: [DriveSummaryItem]

    func load(carId: Int) async -> [DriveSummaryItem] {
        items.filter { $0.carId == carId }
    }

    func save(_: [DriveSummaryItem], carId _: Int) async {}
}

private extension APIResult {
    func successValue() throws -> Value {
        switch self {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

private struct FakeDriveSummaryProvider: DriveSummaryProviding {
    let items: [DriveSummaryItem]

    func driveSummaries(carId _: Int) async -> APIResult<[DriveSummaryItem]> {
        .success(items)
    }

    func driveUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(.metric)
    }
}

private struct DeferredDriveEnrichmentProvider: DriveSummaryProviding {
    let gate: DriveEnrichmentGate

    func driveSummaries(carId _: Int) async -> APIResult<[DriveSummaryItem]> {
        .success([.fixture(driveId: 10, distance: 10, durationMin: 20)])
    }

    func driveUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(.metric)
    }

    func enrichDriveSummaries(_ summaries: [DriveSummaryItem], carId _: Int) async -> [DriveSummaryItem] {
        await gate.waitForRelease()
        return summaries.map { item in
            DriveSummaryItem(
                driveId: item.driveId,
                carId: item.carId,
                startDate: item.startDate,
                endDate: item.endDate,
                distance: item.distance,
                durationMin: item.durationMin,
                energyConsumedNet: 1,
                efficiency: 100,
                efficiencySource: .powerSamples
            )
        }
    }
}

private struct DeferredDriveUnitsProvider: DriveSummaryProviding {
    let gate: DriveEnrichmentGate

    func driveSummaries(carId _: Int) async -> APIResult<[DriveSummaryItem]> {
        .success([.fixture(driveId: 10, distance: 10, durationMin: 20, efficiency: 180, efficiencySource: .api)])
    }

    func driveUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        await gate.waitForRelease()
        return .success(.metric)
    }
}

private struct CacheFirstDriveSummaryProvider: DriveSummaryProviding {
    let gate: DriveEnrichmentGate

    func cachedDriveSummaries(carId _: Int) async -> [DriveSummaryItem] {
        [.fixture(driveId: 41, distance: 12, durationMin: 20)]
    }

    func driveSummaries(carId _: Int) async -> APIResult<[DriveSummaryItem]> {
        await gate.waitForRelease()
        return .success([.fixture(driveId: 42, distance: 13, durationMin: 21)])
    }

    func driveUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(.metric)
    }
}

private actor DriveEnrichmentGate {
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

private func syntheticRouteFingerprint() -> DriveRouteFingerprint {
    DriveRouteFingerprint(points: (0..<4).map { index in
        let point = SyntheticCoordinates.point(
            latitudeOffset: Double(index) * 0.01,
            longitudeOffset: Double(index) * 0.01
        )
        return DriveRoutePoint(latitude: point.latitude, longitude: point.longitude)
    })
}

private extension DriveSummaryItem {
    static func fixture(
        driveId: Int,
        distance: Double,
        durationMin: Int,
        startDate: String = "2026-07-01T08:00:00Z",
        speedMax: Int? = nil,
        efficiency: Double? = nil,
        efficiencySource: DriveEnergySource = .unavailable,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        routeFingerprint: DriveRouteFingerprint? = nil
    ) -> DriveSummaryItem {
        DriveSummaryItem(
            driveId: driveId,
            carId: 1,
            startDate: startDate,
            endDate: "2026-07-01T08:30:00Z",
            distance: distance,
            durationMin: durationMin,
            startAddress: "Home",
            endAddress: "Work",
            speedMax: speedMax,
            speedAvg: nil,
            energyConsumedNet: nil,
            efficiency: efficiency,
            efficiencySource: efficiencySource,
            outsideTempAvg: nil,
            startRatedRangeKm: startRatedRangeKm,
            endRatedRangeKm: endRatedRangeKm,
            routeFingerprint: routeFingerprint
        )
    }
}
