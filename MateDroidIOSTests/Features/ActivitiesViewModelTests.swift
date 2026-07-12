import XCTest
@testable import MateDroidIOS

@MainActor
final class ActivitiesViewModelTests: XCTestCase {
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
        let response = try JSONDecoder.teslamate.decode(
            StandbyDrainResponse.self,
            from: Data(#"{"data":{"latitude":28.2,"longitude":112.8,"radius_meters":100,"period_days":30,"total_parking_events":19,"total_parking_days":14,"avg_drain_rate_km_h":1.338,"avg_drain_rate_pct_24h":-11.97,"total_range_loss_km":252.27,"min_drain_rate_km_h":0.046,"max_drain_rate_km_h":3.285},"units":{"length":"km"}}"#.utf8)
        )
        let api = ActivityTestAPI(activityResults: [], standbyResult: .success(response))
        let viewModel = StandbyDrainViewModel(api: api)

        await viewModel.load(carId: 1, latitude: 28.2, longitude: 112.8)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertNil(viewModel.state.errorMessage)
        XCTAssertEqual(viewModel.state.data?.totalParkingEvents, 19)
        XCTAssertEqual(viewModel.state.data?.averageDrainPercent24H, -11.97)
        XCTAssertEqual(viewModel.state.data?.totalRangeLossKm, 252.27)
        XCTAssertEqual(viewModel.state.units?.length, "km")
        let request = await api.standbyRequest
        XCTAssertEqual(request?.carId, 1)
        XCTAssertEqual(request?.latitude, 28.2)
        XCTAssertEqual(request?.longitude, 112.8)
    }

    func testStandbyDrainFailureDoesNotInventZeroMetrics() async {
        let api = ActivityTestAPI(activityResults: [], standbyResult: .failure(.httpStatus(404)))
        let viewModel = StandbyDrainViewModel(api: api)

        await viewModel.load(carId: 1, latitude: 28.2, longitude: 112.8)

        XCTAssertNil(viewModel.state.data)
        XCTAssertNotNil(viewModel.state.errorMessage)
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

    private func response(_ json: String) throws -> TeslaMateActivitiesResponse {
        try JSONDecoder.teslamate.decode(TeslaMateActivitiesResponse.self, from: Data(json.utf8))
    }
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
    private(set) var requestedPages: [Int] = []
    private(set) var standbyRequest: (carId: Int, latitude: Double, longitude: Double)?

    init(
        activityResults: [APIResult<TeslaMateActivitiesResponse>],
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        standbyResult: APIResult<StandbyDrainResponse> = .failure(.httpStatus(404))
    ) {
        self.activityResults = activityResults
        driveValues = drives
        chargeValues = charges
        self.standbyResult = standbyResult
    }

    func activities(carId _: Int, page: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        requestedPages.append(page)
        return activityResults.isEmpty ? .failure(.emptyBody) : activityResults.removeFirst()
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success(driveValues)
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success(chargeValues)
    }

    func standbyDrain(carId: Int, latitude: Double, longitude: Double) async -> APIResult<StandbyDrainResponse> {
        standbyRequest = (carId, latitude, longitude)
        return standbyResult
    }
}
