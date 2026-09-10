import XCTest
@testable import MateDriveApp

@MainActor
final class ActivitiesViewModelTests: XCTestCase {
    func testCachedSleepSummariesSurviveActivityFailureAndPeriodSwitchDoesNotRequestAPI() async {
        let api = ActivityTestAPI(activityResults: [.failure(.network("offline"))])
        let summaries: [SleepDurationPeriod: SleepDurationSummary] = [
            .sinceCharge: SleepDurationSummary(period: .sinceCharge, duration: 10_800, isAvailable: true),
            .today: SleepDurationSummary(period: .today, duration: 3_600, isAvailable: true),
            .week: SleepDurationSummary(period: .week, duration: 21_600, isAvailable: true),
            .month: SleepDurationSummary(period: .month, duration: nil, isAvailable: false)
        ]
        let viewModel = ActivitiesViewModel(
            api: api,
            sleepSummaryProvider: ActivitySleepSummaryProvider(summaries: summaries)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.sleepSummaries, summaries)
        XCTAssertEqual(viewModel.selectedSleepPeriod, .today)
        XCTAssertEqual(viewModel.selectedSleepSummary, summaries[.today])
        let requestsBeforeSwitch = await api.requestedPages

        viewModel.setSleepPeriod(.month)

        XCTAssertEqual(viewModel.selectedSleepSummary, summaries[.month])
        let requestsAfterSwitch = await api.requestedPages
        XCTAssertEqual(requestsAfterSwitch, requestsBeforeSwitch)
    }

    func testBroken241PaginationLoadsOnePageAtATimeDeduplicatesAndStopsOnNoNewIDs() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":3,"type":"park","startDate":"2026-07-03T00:00:00Z"},{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"totalRecords":0,"totalPages":9999,"page":1,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"},{"id":1,"type":"charge","startDate":"2026-07-01T00:00:00Z"}],"pagination":{"totalRecords":0,"totalPages":9999,"page":2,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":2,"type":"drive"},{"id":1,"type":"charge"}],"pagination":{"totalRecords":0,"totalPages":9999,"page":3,"limit":2}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)
        XCTAssertEqual(viewModel.state.items.map(\.stableID), ["park-3", "drive-2"])
        XCTAssertTrue(viewModel.state.paginationIsDegraded)
        XCTAssertTrue(viewModel.state.hasMore)

        await viewModel.loadMoreIfNeeded(currentItem: try XCTUnwrap(viewModel.filteredItems.last))
        XCTAssertEqual(viewModel.state.items.map(\.stableID), ["park-3", "drive-2", "charge-1"])
        XCTAssertTrue(viewModel.state.hasMore)

        await viewModel.loadMoreIfNeeded(currentItem: try XCTUnwrap(viewModel.filteredItems.last))
        XCTAssertFalse(viewModel.state.hasMore)
        let pages = await api.requestedPages
        XCTAssertEqual(pages, [1, 2, 3])
    }

    func testUnavailableActivitiesEndpointFallsBackWithoutInventingParking() async {
        let api = ActivityTestAPI(
            activityResults: [.failure(.httpStatus(404))],
            drives: [DriveData(driveId: 7, startDate: "2026-07-02T00:00:00Z", distance: 12, durationMin: 30)],
            charges: [ChargeData(chargeId: 8, startDate: "2026-07-01T00:00:00Z", address: "Home", chargeEnergyAdded: 20)]
        )
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.source, .localFallback)
        XCTAssertEqual(viewModel.state.items.map(\.kind), [.drive, .charge])
        XCTAssertFalse(viewModel.state.items.contains { $0.kind == .park })
        XCTAssertFalse(viewModel.state.hasMore)
    }

    func testUnavailableActivitiesEndpointUsesLocalHistoryWithoutLargeHistoryRequests() async {
        let api = ActivityTestAPI(
            activityResults: [.failure(.httpStatus(404))],
            drives: [DriveData(driveId: 999)]
        )
        let viewModel = ActivitiesViewModel(
            api: api,
            historyProvider: ActivityHistoryProvider(
                drives: [DriveData(driveId: 7, startDate: "2026-07-02T00:00:00Z", distance: 12)],
                charges: [ChargeData(chargeId: 8, startDate: "2026-07-01T00:00:00Z", chargeEnergyAdded: 20)]
            )
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(Set(viewModel.state.items.map(\.stableID)), ["drive-7", "charge-8"])
        let historyRequestCount = await api.historyRequestCount
        XCTAssertEqual(historyRequestCount, 0)
    }

    func testEmptyActivitiesResponseFallsBackAndPreservesChargeCost() async throws {
        let api = ActivityTestAPI(
            activityResults: [.success(try response(#"{"data":[],"pagination":{"totalRecords":0,"totalPages":9999,"page":1,"limit":20},"units":{"unit_of_length":"mi","unit_of_temperature":"F","unit_of_pressure":"psi"}}"#))],
            drives: [DriveData(driveId: 7, startDate: "2026-07-02T00:00:00Z", distance: 12, durationMin: 30)],
            charges: [
                ChargeData(chargeId: 8, startDate: "2026-07-01T00:00:00Z", address: "Home", chargeEnergyAdded: 20, cost: 12.5),
                ChargeData(chargeId: 9, startDate: "2026-06-30T00:00:00Z", address: "Office", chargeEnergyAdded: 10, cost: nil)
            ]
        )
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.source, .localFallback)
        let charge = try XCTUnwrap(viewModel.state.items.first { $0.kind == .charge })
        XCTAssertEqual(charge.cost, 12.5)
        XCTAssertTrue(viewModel.state.historyFullyLoaded)
        XCTAssertEqual(viewModel.state.units, .imperial)
        XCTAssertEqual(viewModel.periodSummary.knownChargeCost, 12.5)
        XCTAssertEqual(viewModel.periodSummary.pricedChargeCount, 1)
        XCTAssertEqual(viewModel.periodSummary.missingChargeCostCount, 1)
        XCTAssertFalse(viewModel.periodSummary.chargeCostIsComplete)
    }

    func testCompleteUnifiedActivitiesEnrichMissingCostsFromChargeHistory() async throws {
        let api = ActivityTestAPI(
            activityResults: [.success(try response(#"{"data":[{"id":8,"type":"charge","startDate":"2026-07-01T00:00:00Z","startAddress":"Home","kwh":20}],"pagination":{"page":1,"limit":20}}"#))],
            charges: [ChargeData(chargeId: 8, startDate: "2026-07-01T00:00:00Z", address: "Home", chargeEnergyAdded: 20, cost: 12.5)]
        )
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.source, .unifiedAPI)
        XCTAssertEqual(viewModel.state.items.first?.cost, 12.5)
        XCTAssertEqual(viewModel.periodSummary.knownChargeCost, 12.5)
        XCTAssertTrue(viewModel.periodSummary.chargeCostIsComplete)
    }

    func testLocationFilterMatchesEitherEndpointAndKeepsCrossTypeIDsDistinct() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":7,"type":"drive","startAddress":"Home","endAddress":"Office","startLatitude":28.2,"startLongitude":112.9},{"id":7,"type":"charge","startAddress":"Mall Supercharger","startLatitude":28.1,"startLongitude":112.8},{"id":8,"type":"park","startAddress":"Airport","startLatitude":999,"startLongitude":112.7}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)
        XCTAssertEqual(viewModel.state.items.map(\.stableID), ["drive-7", "charge-7", "park-8"])
        XCTAssertEqual(viewModel.mappableItems.map(\.stableID), ["drive-7", "charge-7"])

        viewModel.setLocationQuery("office")
        XCTAssertEqual(viewModel.filteredItems.map(\.stableID), ["drive-7"])

        viewModel.setLocationQuery("  MALL ")
        XCTAssertEqual(viewModel.filteredItems.map(\.stableID), ["charge-7"])
    }

    func testExplicitLoadMoreSupportsMapWithoutListOnAppear() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":2,"type":"drive"},{"id":1,"type":"charge"}],"pagination":{"page":1,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":3,"type":"park"}],"pagination":{"page":2,"limit":2}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)
        XCTAssertTrue(viewModel.state.hasMore)
        await viewModel.loadMore()

        XCTAssertEqual(Set(viewModel.state.items.map(\.stableID)), ["drive-2", "charge-1", "park-3"])
        XCTAssertFalse(viewModel.state.hasMore)
        let pages = await api.requestedPages
        XCTAssertEqual(pages, [1, 2])
    }

    func testCompleteHistoryMakesDateLocationFiltersAndPeriodSummaryExplicit() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":3,"type":"drive","startDate":"2026-07-10T00:00:00Z","startAddress":"Home","endAddress":"Office","distanceKm":30,"kwh":-5},{"id":2,"type":"charge","startDate":"2026-07-05T00:00:00Z","startAddress":"Home","kwh":20,"cost":6}],"pagination":{"page":1,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":1,"type":"park","startDate":"2026-05-01T00:00:00Z","startAddress":"Airport","durationMin":120}],"pagination":{"page":2,"limit":2}}"#))
        ])
        let now = try XCTUnwrap(DomainDateParser.date(from: "2026-07-11T00:00:00Z"))
        let viewModel = ActivitiesViewModel(api: api, now: { now })

        await viewModel.load(carId: 1)
        XCTAssertFalse(viewModel.state.historyFullyLoaded)

        await viewModel.loadCompleteHistory()
        XCTAssertTrue(viewModel.state.historyFullyLoaded)
        XCTAssertEqual(viewModel.state.loadedPageCount, 2)

        viewModel.setDateFilter(.sevenDays)
        viewModel.setLocationQuery("home")
        XCTAssertEqual(viewModel.filteredItems.map(\.stableID), ["drive-3", "charge-2"])
        XCTAssertEqual(viewModel.periodSummary.activityCount, 2)
        XCTAssertEqual(viewModel.periodSummary.driveCount, 1)
        XCTAssertEqual(viewModel.periodSummary.chargeCount, 1)
        XCTAssertEqual(viewModel.periodSummary.parkingCount, 0)
        XCTAssertEqual(viewModel.periodSummary.distanceKm, 30)
        XCTAssertEqual(viewModel.periodSummary.chargedEnergyKWh, 20)
        XCTAssertEqual(viewModel.periodSummary.drivingEnergyKWh, 5)
        XCTAssertEqual(viewModel.periodSummary.knownChargeCost, 6)
        XCTAssertEqual(viewModel.periodSummary.pricedChargeCount, 1)
        XCTAssertEqual(viewModel.periodSummary.missingChargeCostCount, 0)
        XCTAssertTrue(viewModel.periodSummary.chargeCostIsComplete)
    }

    func testPeriodSummaryReportsCoverageForMissingDistanceAndEnergy() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":1,"type":"drive","distanceKm":30,"kwhUsed":5},{"id":2,"type":"drive"},{"id":3,"type":"charge","kwh":20},{"id":4,"type":"charge"}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        let summary = viewModel.periodSummary
        XCTAssertEqual(summary.distanceKm, 30)
        XCTAssertEqual(summary.distanceRecordCount, 1)
        XCTAssertFalse(summary.distanceIsComplete)
        XCTAssertEqual(summary.drivingEnergyKWh, 5)
        XCTAssertEqual(summary.drivingEnergyRecordCount, 1)
        XCTAssertFalse(summary.drivingEnergyIsComplete)
        XCTAssertEqual(summary.chargedEnergyKWh, 20)
        XCTAssertEqual(summary.chargedEnergyRecordCount, 1)
        XCTAssertFalse(summary.chargedEnergyIsComplete)
        XCTAssertEqual(ActivitySummaryPresentation.energyText(5, isComplete: false), "≥5.0 kWh")
        XCTAssertEqual(ActivitySummaryPresentation.energyText(nil, isComplete: false), "--")
        XCTAssertEqual(ActivitySummaryPresentation.distanceText(nil, isComplete: false, units: .metric), "--")
    }

    func testPeriodDateRangeUsesEarliestStartAndLatestEndAcrossFilteredActivities() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":1,"type":"drive","startDate":"2026-07-02T08:00:00Z","endDate":"2026-07-02T09:00:00Z"},{"id":2,"type":"charge","startDate":"2026-07-03T10:00:00Z","endDate":"2026-07-03T11:00:00Z"}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.periodDateRange?.start, DomainDateParser.date(from: "2026-07-02T08:00:00Z"))
        XCTAssertEqual(viewModel.periodDateRange?.end, DomainDateParser.date(from: "2026-07-03T11:00:00Z"))
        viewModel.setFilter(.charge)
        XCTAssertEqual(viewModel.periodDateRange?.start, DomainDateParser.date(from: "2026-07-03T10:00:00Z"))
    }

    func testCompleteHistoryReportsCapInsteadOfClaimingCompleteness() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":3,"type":"drive"},{"id":2,"type":"drive"}],"pagination":{"page":1,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":1,"type":"drive"},{"id":4,"type":"drive"}],"pagination":{"page":2,"limit":2}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)
        await viewModel.loadCompleteHistory(maximumPages: 2)

        XCTAssertTrue(viewModel.state.historyLoadCapped)
        XCTAssertFalse(viewModel.state.historyFullyLoaded)
        XCTAssertTrue(viewModel.state.hasMore)
    }

    func testListPaginationDoesNotCompeteWithCompleteHistoryLoad() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":2,"type":"drive"},{"id":1,"type":"charge"}],"pagination":{"page":1,"limit":2}}"#)),
            .success(try response(#"{"data":[{"id":3,"type":"park"}],"pagination":{"page":2,"limit":2}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)
        await viewModel.load(carId: 1)
        let last = try XCTUnwrap(viewModel.filteredItems.last)

        async let complete: Void = viewModel.loadCompleteHistory()
        async let listPaging: Void = viewModel.loadMoreIfNeeded(currentItem: last)
        _ = await (complete, listPaging)

        XCTAssertTrue(viewModel.state.historyFullyLoaded)
        let pages = await api.requestedPages
        XCTAssertEqual(pages, [1, 2])
    }

    func testPeriodSummaryAppliesPersistedParkingRulesAndReportsUnmatchedRecords() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":1,"type":"park","startDate":"2026-07-01T00:00:00Z","startAddress":"Mall","durationMin":150},{"id":2,"type":"park","startDate":"2026-07-02T00:00:00Z","startAddress":"Street","durationMin":60}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let settings = AppSettings(currencyCode: "CNY", parkingFeeRules: [
            ParkingFeeRule(name: "Mall", addressKeyword: "Mall", freeMinutes: 30, billingIncrementMinutes: 60, hourlyRate: 5)
        ])
        let viewModel = ActivitiesViewModel(api: api, settingsStore: StaticActivitySettingsStore(settings: settings))

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.currencyCode, "CNY")
        XCTAssertEqual(viewModel.periodSummary.parkingCost.totalCost, 10)
        XCTAssertEqual(viewModel.periodSummary.parkingCost.matchedParkingCount, 1)
        XCTAssertEqual(viewModel.periodSummary.parkingCost.unmatchedParkingCount, 1)
    }

    func testStandbyDrainDecodesMeasuredFieldsAndViewModelPreservesSignedChange() async throws {
        let location = SyntheticCoordinates.point()
        let response = try JSONDecoder.teslamate.decode(
            StandbyDrainResponse.self,
            from: Data(#"{"data":{"latitude":\#(location.latitude),"longitude":\#(location.longitude),"radius_meters":100,"period_days":30,"total_parking_events":19,"total_parking_days":14,"avg_drain_rate_km_h":1.338,"avg_drain_rate_pct_24h":-11.97,"total_range_loss_km":252.27,"min_drain_rate_km_h":0.046,"max_drain_rate_km_h":3.285},"units":{"length":"km"}}"#.utf8)
        )
        let api = ActivityTestAPI(activityResults: [], standbyResult: .success(response))
        let viewModel = StandbyDrainViewModel(api: api)

        await viewModel.load(carId: 1, latitude: location.latitude, longitude: location.longitude)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertNil(viewModel.state.errorMessage)
        XCTAssertEqual(viewModel.state.data?.totalParkingEvents, 19)
        XCTAssertEqual(viewModel.state.data?.averageDrainPercent24H, -11.97)
        XCTAssertEqual(viewModel.state.data?.totalRangeLossKm, 252.27)
        XCTAssertEqual(viewModel.state.units?.length, "km")
        let request = await api.standbyRequest
        XCTAssertEqual(request?.carId, 1)
        XCTAssertEqual(request?.latitude, location.latitude)
        XCTAssertEqual(request?.longitude, location.longitude)
    }

    func testStandbyDrainFailureDoesNotInventZeroMetrics() async {
        let api = ActivityTestAPI(activityResults: [], standbyResult: .failure(.httpStatus(404)))
        let viewModel = StandbyDrainViewModel(api: api)
        let location = SyntheticCoordinates.point()

        await viewModel.load(carId: 1, latitude: location.latitude, longitude: location.longitude)

        XCTAssertNil(viewModel.state.data)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    func testStandbyDrainRepeatedEntryRestoresDataAndFailedRefreshPreservesIt() async throws {
        let location = SyntheticCoordinates.point()
        let response = try JSONDecoder.teslamate.decode(
            StandbyDrainResponse.self,
            from: Data(#"{"data":{"latitude":\#(location.latitude),"longitude":\#(location.longitude),"total_parking_events":3,"total_range_loss_km":12.5},"units":{"length":"km"}}"#.utf8)
        )
        let cache = VehiclePageStateCache<StandbyDrainState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1,
            scope: StandbyDrainViewModel.cacheScope(
                latitude: location.latitude,
                longitude: location.longitude
            )
        )
        let initial = StandbyDrainViewModel(
            api: ActivityTestAPI(activityResults: [], standbyResult: .success(response)),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(
            carId: 1,
            latitude: location.latitude,
            longitude: location.longitude
        )

        let reopened = StandbyDrainViewModel(
            api: ActivityTestAPI(
                activityResults: [],
                standbyResult: .failure(.network("offline"))
            ),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.data?.totalRangeLossKm, 12.5)

        await reopened.load(
            carId: 1,
            latitude: location.latitude,
            longitude: location.longitude
        )

        XCTAssertEqual(reopened.state.data?.totalRangeLossKm, 12.5)
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testStandbyDrainCachesResolvedEmptyResponse() async throws {
        let location = SyntheticCoordinates.point()
        let response = try JSONDecoder.teslamate.decode(
            StandbyDrainResponse.self,
            from: Data(#"{"data":null,"error":"No parking samples","units":{"length":"km"}}"#.utf8)
        )
        let cache = VehiclePageStateCache<StandbyDrainState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1,
            scope: "standby-empty"
        )
        let initial = StandbyDrainViewModel(
            api: ActivityTestAPI(activityResults: [], standbyResult: .success(response)),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(
            carId: 1,
            latitude: location.latitude,
            longitude: location.longitude
        )

        let reopened = StandbyDrainViewModel(
            api: ActivityTestAPI(activityResults: []),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertNil(reopened.state.data)
        XCTAssertEqual(reopened.state.errorMessage, "No parking samples")
        XCTAssertFalse(reopened.state.isLoading)
    }

    func testOverlappingStandbyDrainLoadsStartOneRequest() async {
        let location = SyntheticCoordinates.point()
        let api = SlowStandbyDrainAPI()
        let viewModel = StandbyDrainViewModel(api: api)

        async let first: Void = viewModel.load(
            carId: 1,
            latitude: location.latitude,
            longitude: location.longitude
        )
        async let second: Void = viewModel.load(
            carId: 1,
            latitude: location.latitude,
            longitude: location.longitude
        )
        _ = await (first, second)

        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testStandbyDrainCacheScopeSeparatesNearbyLocations() {
        let first = SyntheticCoordinates.point()
        let second = SyntheticCoordinates.point(latitudeOffset: 0.00001)

        XCTAssertNotEqual(
            StandbyDrainViewModel.cacheScope(latitude: first.latitude, longitude: first.longitude),
            StandbyDrainViewModel.cacheScope(latitude: second.latitude, longitude: second.longitude)
        )
    }

    func testActivitiesPreserveServerUnitsForPresentation() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[],"pagination":{"page":1,"limit":20},"units":{"unit_of_length":"mi","unit_of_temperature":"F","unit_of_pressure":"psi"}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.units, .imperial)
    }

    func testActivitiesClearUnitsBeforeLoadingAnotherServer() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[],"pagination":{"page":1,"limit":20}}"#))
        ])
        var initialState = ActivitiesState()
        initialState.units = .imperial
        let viewModel = ActivitiesViewModel(api: api, initialState: initialState)

        await viewModel.load(carId: 2)

        XCTAssertNil(viewModel.state.units)
    }

    func testReopeningActivitiesShowsCachedRowsWhileRefreshing() async throws {
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settingsStore = StaticActivitySettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let firstAPI = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":1,"type":"drive","startAddress":"Cached drive"}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let firstViewModel = ActivitiesViewModel(api: firstAPI, settingsStore: settingsStore, cache: cache)
        await firstViewModel.load(carId: 1)

        let refreshedAPI = ActivityTestAPI(
            activityResults: [
                .success(try response(#"{"data":[{"id":2,"type":"drive","startAddress":"Fresh drive"}],"pagination":{"page":1,"limit":20}}"#))
            ],
            delayNanoseconds: 400_000_000
        )
        let reopenedViewModel = ActivitiesViewModel(api: refreshedAPI, settingsStore: settingsStore, cache: cache)

        let refresh = Task { await reopenedViewModel.load(carId: 1) }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(reopenedViewModel.state.items.map(\.stableID), ["drive-1"])
        XCTAssertTrue(reopenedViewModel.state.isLoading)
        XCTAssertTrue(reopenedViewModel.state.isUsingCachedData)

        await refresh.value
        XCTAssertEqual(Set(reopenedViewModel.state.items.map(\.stableID)), ["drive-1", "drive-2"])
        XCTAssertFalse(reopenedViewModel.state.isLoading)
        XCTAssertTrue(reopenedViewModel.state.isUsingCachedData)
    }

    func testReopeningActivitiesPreservesPartiallyPreloadedHistory() async throws {
        let cache = ActivitiesStateCache(maximumAge: 60)
        let settings = AppSettings(serverURL: "https://teslamate.example")
        let settingsStore = StaticActivitySettingsStore(settings: settings)
        var cachedState = ActivitiesState()
        cachedState.items = [
            TeslaMateActivity(id: 1, type: "drive", startDate: "2026-07-01T00:00:00Z")
        ]
        cachedState.hasMore = true
        cachedState.loadedPageCount = 1
        cachedState.historyFullyLoaded = false
        await cache.save(
            ActivitiesCacheSnapshot(state: cachedState),
            serverURL: settings.serverURL,
            carId: 1
        )
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":2,"type":"drive","startDate":"2026-07-02T00:00:00Z"}],"pagination":{"page":1,"limit":20,"totalPages":2,"totalRecords":2}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api, settingsStore: settingsStore, cache: cache)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.items.map(\.stableID), ["drive-2", "drive-1"])
        XCTAssertTrue(viewModel.state.hasMore)
        XCTAssertFalse(viewModel.state.historyFullyLoaded)
    }

    func testActivitiesCachePersistsCompleteHistoryAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activities-cache-\(UUID().uuidString)", isDirectory: true)
        let storageURL = directory.appendingPathComponent("cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_752_192_000)
        var state = ActivitiesState()
        state.items = [TeslaMateActivity(id: 1, type: "drive", startDate: "2025-07-10T00:00:00Z")]
        state.historyFullyLoaded = true
        state.loadedPageCount = 4

        let writer = ActivitiesStateCache(maximumAge: 60, storageURL: storageURL)
        await writer.save(
            ActivitiesCacheSnapshot(state: state, savedAt: now),
            serverURL: "https://teslamate.example",
            carId: 7
        )
        let reader = ActivitiesStateCache(maximumAge: 60, storageURL: storageURL)

        let restored = await reader.load(
            serverURL: "https://teslamate.example",
            carId: 7,
            now: now.addingTimeInterval(10)
        )

        XCTAssertEqual(restored?.state.items.map(\.stableID), ["drive-1"])
        XCTAssertEqual(restored?.state.loadedPageCount, 4)
        XCTAssertTrue(restored?.state.historyFullyLoaded == true)
        XCTAssertTrue(restored?.state.isUsingCachedData == true)
        let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        XCTAssertTrue(
            protection == nil || protection == .completeUntilFirstUserAuthentication,
            "The simulator may omit NSFileProtectionKey, but must not report a weaker explicit protection class."
        )
#else
        XCTAssertEqual(
            protection,
            .completeUntilFirstUserAuthentication
        )
#endif

        await reader.removeAll()
        let afterRemoval = ActivitiesStateCache(maximumAge: 60, storageURL: storageURL)
        let cleared = await afterRemoval.load(
            serverURL: "https://teslamate.example",
            carId: 7,
            now: now.addingTimeInterval(10)
        )
        XCTAssertNil(cleared)
    }

    func testActivitiesCacheReleaseMemoryPreservesDiskFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activities-memory-cache-\(UUID().uuidString)", isDirectory: true)
        let storageURL = directory.appendingPathComponent("cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_752_192_000)
        var state = ActivitiesState()
        state.items = [TeslaMateActivity(id: 8, type: "drive")]
        let cache = ActivitiesStateCache(maximumAge: 60, storageURL: storageURL)
        await cache.save(
            ActivitiesCacheSnapshot(state: state, savedAt: now),
            serverURL: "https://teslamate.example",
            carId: 7
        )

        await cache.releaseMemory()
        let restored = await cache.load(
            serverURL: "https://teslamate.example",
            carId: 7,
            now: now.addingTimeInterval(10)
        )

        XCTAssertEqual(restored?.state.items.map(\.stableID), ["drive-8"])
    }

    func testActivityCacheDoesNotReplaceCompleteHistoryWithEarlierPreloadCheckpoint() async {
        let cache = ActivitiesStateCache(maximumAge: 60)
        var complete = ActivitiesState()
        complete.items = [
            TeslaMateActivity(id: 4, type: "drive"),
            TeslaMateActivity(id: 3, type: "charge")
        ]
        complete.loadedPageCount = 4
        complete.historyFullyLoaded = true
        complete.hasMore = false
        await cache.save(
            ActivitiesCacheSnapshot(state: complete),
            serverURL: "https://teslamate.example",
            carId: 1
        )

        var checkpoint = ActivitiesState()
        checkpoint.items = [TeslaMateActivity(id: 5, type: "drive")]
        checkpoint.loadedPageCount = 1
        checkpoint.historyFullyLoaded = false
        checkpoint.hasMore = true
        await cache.save(
            ActivitiesCacheSnapshot(state: checkpoint),
            serverURL: "https://teslamate.example",
            carId: 1
        )

        let restored = await cache.load(
            serverURL: "https://teslamate.example",
            carId: 1,
            now: Date()
        )
        XCTAssertEqual(restored?.state.items.map(\.stableID), ["drive-4", "charge-3"])
        XCTAssertEqual(restored?.state.loadedPageCount, 4)
        XCTAssertTrue(restored?.state.historyFullyLoaded == true)
    }

    func testTimelineMergesAdjacentDrivesWithoutChangingPeriodRecordCounts() async throws {
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[{"id":3,"type":"drive","startDate":"2026-07-15T10:10:00Z","endDate":"2026-07-15T10:30:00Z","startAddress":"Coffee","endAddress":"Office","distanceKm":5},{"id":2,"type":"park","startDate":"2026-07-15T10:00:00Z","endDate":"2026-07-15T10:10:00Z","startAddress":"Coffee","durationMin":10},{"id":1,"type":"drive","startDate":"2026-07-15T09:30:00Z","endDate":"2026-07-15T10:00:00Z","startAddress":"Home","endAddress":"Coffee","distanceKm":10}],"pagination":{"page":1,"limit":20}}"#))
        ])
        let settingsStore = StaticActivitySettingsStore(settings: AppSettings(
            serverURL: "https://teslamate.example",
            mergeAdjacentDrives: true,
            adjacentDriveMergeMaximumGapMinutes: 30
        ))
        let viewModel = ActivitiesViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.timelineEntries.count, 1)
        XCTAssertEqual(viewModel.mergedDriveGroupCount, 1)
        XCTAssertEqual(viewModel.periodSummary.activityCount, 3)
        XCTAssertEqual(viewModel.periodSummary.driveCount, 2)
        XCTAssertEqual(viewModel.periodSummary.parkingCount, 1)
        guard case let .mergedDrive(group) = try XCTUnwrap(viewModel.timelineEntries.first) else {
            return XCTFail("Expected merged timeline entry")
        }
        XCTAssertEqual(group.drives.map(\.id), [1, 3])
        XCTAssertEqual(group.intermediateParking.map(\.id), [2])
    }

    func testAdjacentDriveMergePreferencesLoadAndPersist() async throws {
        let settingsStore = StaticActivitySettingsStore(settings: AppSettings(
            serverURL: "https://teslamate.example",
            mergeAdjacentDrives: false,
            adjacentDriveMergeMaximumGapMinutes: 60
        ))
        let api = ActivityTestAPI(activityResults: [
            .success(try response(#"{"data":[],"pagination":{"page":1,"limit":20}}"#))
        ])
        let viewModel = ActivitiesViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1)
        XCTAssertFalse(viewModel.mergeConfiguration.isEnabled)
        XCTAssertEqual(viewModel.mergeConfiguration.maximumGapMinutes, 60)

        await viewModel.setAdjacentDriveMergingEnabled(true)
        await viewModel.setAdjacentDriveMergeMaximumGapMinutes(120)

        let saved = await settingsStore.load()
        XCTAssertTrue(saved.mergeAdjacentDrives)
        XCTAssertEqual(saved.adjacentDriveMergeMaximumGapMinutes, 120)
    }

    private func response(_ json: String) throws -> TeslaMateActivitiesResponse {
        try JSONDecoder.teslamate.decode(TeslaMateActivitiesResponse.self, from: Data(json.utf8))
    }
}

private struct ActivitySleepSummaryProvider: DashboardSummaryProviding {
    let summaries: [SleepDurationPeriod: SleepDurationSummary]

    func summary(carId _: Int) async throws -> DashboardCachedSummary {
        DashboardCachedSummary(
            latestDrive: nil,
            latestCharge: nil,
            odometerKm: nil,
            sleepSummaries: summaries
        )
    }
}

private struct ActivityHistoryProvider: MileageDataProviding {
    let drives: [DriveData]
    let charges: [ChargeData]

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> { .success(drives) }
    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> { .success(charges) }
    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> { .success(.metric) }
}

private actor StaticActivitySettingsStore: SettingsStoring {
    private var value: AppSettings
    init(settings: AppSettings) { value = settings }
    func load() async -> AppSettings { value }
    func save(_ settings: AppSettings) async { value = settings }
}

private actor ActivityTestAPI: ActivityAPIProviding {
    private var activityResults: [APIResult<TeslaMateActivitiesResponse>]
    private let driveValues: [DriveData]
    private let chargeValues: [ChargeData]
    private let standbyResult: APIResult<StandbyDrainResponse>
    private let delayNanoseconds: UInt64
    private(set) var requestedPages: [Int] = []
    private(set) var historyRequestCount = 0
    private(set) var standbyRequest: (carId: Int, latitude: Double, longitude: Double)?

    init(
        activityResults: [APIResult<TeslaMateActivitiesResponse>],
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        standbyResult: APIResult<StandbyDrainResponse> = .failure(.httpStatus(404)),
        delayNanoseconds: UInt64 = 0
    ) {
        self.activityResults = activityResults
        driveValues = drives
        chargeValues = charges
        self.standbyResult = standbyResult
        self.delayNanoseconds = delayNanoseconds
    }

    func activities(carId _: Int, page: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        requestedPages.append(page)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return activityResults.isEmpty ? .failure(.emptyBody) : activityResults.removeFirst()
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        historyRequestCount += 1
        return (page ?? 1) == 1 ? .success(driveValues) : .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        historyRequestCount += 1
        return (page ?? 1) == 1 ? .success(chargeValues) : .success([])
    }

    func standbyDrain(carId: Int, latitude: Double, longitude: Double) async -> APIResult<StandbyDrainResponse> {
        standbyRequest = (carId, latitude, longitude)
        return standbyResult
    }
}

private actor SlowStandbyDrainAPI: ActivityAPIProviding {
    private var requests = 0

    var requestCount: Int {
        requests
    }

    func activities(carId _: Int, page _: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        .failure(.emptyBody)
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func standbyDrain(carId _: Int, latitude _: Double, longitude _: Double) async -> APIResult<StandbyDrainResponse> {
        requests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .failure(.emptyBody)
    }
}
