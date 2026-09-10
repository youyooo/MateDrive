import XCTest
@testable import MateDriveApp

@MainActor
final class PlaceInsightsViewModelTests: XCTestCase {
    func testAggregationMergesNormalizedAddressesAndPreservesSourceMetrics() throws {
        let activities = [
            TeslaMateActivity(id: 1, type: "drive", startDate: "2026-07-01T08:00:00Z", endDate: "2026-07-01T08:30:00Z", startAddress: " Home ", endAddress: "Office", startLatitude: 28.1, startLongitude: 112.8, endLatitude: 28.2, endLongitude: 112.9, kwh: -5, distanceKm: 20),
            TeslaMateActivity(id: 2, type: "charge", startDate: "2026-07-02T08:00:00Z", durationMin: 40, startAddress: "home", startLatitude: 28.1, startLongitude: 112.8, kwh: 18, cost: 7.5),
            TeslaMateActivity(id: 3, type: "park", startDate: "2026-07-03T08:00:00Z", durationMin: 120, startAddress: "HOME", startLatitude: 28.1, startLongitude: 112.8),
            TeslaMateActivity(id: 4, type: "park", startAddress: "   ")
        ]

        let places = PlaceInsightsViewModel.aggregate(activities)
        let home = try XCTUnwrap(places.first { $0.name.localizedCaseInsensitiveContains("home") })
        let office = try XCTUnwrap(places.first { $0.name == "Office" })

        XCTAssertEqual(places.count, 2)
        XCTAssertEqual(home.departureCount, 1)
        XCTAssertEqual(home.arrivalCount, 0)
        XCTAssertEqual(home.chargeCount, 1)
        XCTAssertEqual(home.parkingCount, 1)
        XCTAssertEqual(home.chargedEnergyKWh, 18)
        XCTAssertEqual(home.parkingMinutes, 120)
        XCTAssertEqual(home.parkingCost, 0)
        XCTAssertEqual(home.chargeCost, 7.5)
        XCTAssertEqual(home.pricedChargeCount, 1)
        XCTAssertEqual(home.chargeCostIsComplete, true)
        XCTAssertEqual(home.totalEvents, 3)
        XCTAssertEqual(home.latitude, 28.1)
        XCTAssertEqual(office.arrivalCount, 1)
    }

    func testPlaceAggregationCountsMonthlyParkingOnceWithinMonth() throws {
        let activities = [
            TeslaMateActivity(id: 1, type: "park", startDate: "2026-07-01T00:00:00Z", durationMin: 60, startAddress: "Home"),
            TeslaMateActivity(id: 2, type: "park", startDate: "2026-07-20T00:00:00Z", durationMin: 60, startAddress: "Home")
        ]
        let rule = ParkingFeeRule(id: "monthly", name: "Home Monthly", addressKeyword: "Home", monthlyFee: 300)

        let place = try XCTUnwrap(PlaceInsightsViewModel.aggregate(activities, parkingFeeRules: [rule]).first)

        XCTAssertEqual(place.parkingCount, 2)
        XCTAssertEqual(place.parkingCost, 300)
    }

    func testLoadUsesCompleteHistoryAndSupportsPlaceSearch() async throws {
        let api = PlaceActivityTestAPI(results: [
            .success(try decode(#"{"data":[{"id":2,"type":"charge","startDate":"2026-07-02T00:00:00Z","startAddress":"Mall","kwh":12},{"id":1,"type":"drive","startDate":"2026-07-01T00:00:00Z","startAddress":"Home","endAddress":"Mall"}],"pagination":{"page":1,"limit":2}}"#)),
            .success(try decode(#"{"data":[{"id":3,"type":"park","startDate":"2026-06-30T00:00:00Z","startAddress":"Home","durationMin":60}],"pagination":{"page":2,"limit":2}}"#))
        ])
        let viewModel = PlaceInsightsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.historyFullyLoaded)
        XCTAssertEqual(viewModel.state.activityCount, 3)
        XCTAssertEqual(viewModel.state.places.count, 2)
        XCTAssertEqual(viewModel.state.currencyCode, MateDriveCurrencyFormatter.systemCurrencyCode())
        viewModel.setQuery("mall")
        XCTAssertEqual(viewModel.filteredPlaces.map(\.name), ["Mall"])
    }

    func testLoadPrefersCompleteServerPlacePaginationAndPreservesMissingCosts() async throws {
        let server = ServerPlacesTestAPI(results: [
            .success(try decodePlaces(#"{"data":[{"id":6,"displayName":"Home","latitude":28.2,"longitude":112.8,"role":"frequentPlace","roleConfidence":"high","visitCount":99,"activeDays":16,"driveStartCount":32,"driveEndCount":33,"chargeCount":10,"parkCount":24,"totalChargeKwh":234.16,"missingChargeCostCount":10,"totalParkingDurationMin":11503,"parkingRangeLossKm":276.75}],"pagination":{"totalRecords":2,"totalPages":2,"page":1,"limit":1},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}"#)),
            .success(try decodePlaces(#"{"data":[{"id":5,"displayName":"Charge Hub","latitude":28.18,"longitude":112.88,"role":"chargingHub","visitCount":7,"chargeCount":3,"parkCount":0,"totalChargeKwh":72.94,"totalChargeCost":27.83,"missingChargeCostCount":2}],"pagination":{"totalRecords":2,"totalPages":2,"page":2,"limit":1},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}"#))
        ])
        let activity = PlaceActivityTestAPI(results: [.failure(.network("fallback should not load"))])
        let viewModel = PlaceInsightsViewModel(
            api: activity,
            placesAPI: server,
            settingsStore: StaticPlaceSettingsStore(settings: AppSettings(currencyCode: MateDriveCurrencyFormatter.automaticCode))
        )

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.usesServerPlaces)
        XCTAssertTrue(viewModel.state.historyFullyLoaded)
        XCTAssertEqual(viewModel.state.currencyCode, MateDriveCurrencyFormatter.systemCurrencyCode())
        XCTAssertEqual(viewModel.state.places.map(\.name), ["Home", "Charge Hub"])
        let home = try XCTUnwrap(viewModel.state.places.first)
        XCTAssertEqual(home.visitCount, 99)
        XCTAssertEqual(home.parkingRangeLossKm, 276.75)
        XCTAssertFalse(home.parkingCostAvailable)
        XCTAssertNil(home.chargeCost)
        XCTAssertTrue(home.chargedEnergyAvailable)
        XCTAssertTrue(home.parkingMinutesAvailable)
        XCTAssertEqual(home.pricedChargeCount, 0)
        XCTAssertEqual(home.chargeCostIsComplete, false)
        let hub = try XCTUnwrap(viewModel.state.places.last)
        XCTAssertEqual(hub.chargeCost, 27.83)
        XCTAssertEqual(hub.pricedChargeCount, 1)
        XCTAssertEqual(hub.chargeCostIsComplete, false)
        let requestedPages = await server.requestedPages
        XCTAssertEqual(requestedPages, [1, 2])
    }

    func testLocalPlaceSummaryAppearsBeforeSlowServerAndActivityFallbacksComplete() async {
        let summary = StaticPlaceSummaryProvider(activities: [
            TeslaMateActivity(
                id: 1,
                type: "drive",
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T08:30:00Z",
                startAddress: "Home",
                endAddress: "Office",
                distanceKm: 20
            )
        ])
        let server = DelayedServerPlacesTestAPI(delay: .milliseconds(250))
        let activity = PlaceActivityTestAPI(results: [.failure(.network("offline"))])
        let viewModel = PlaceInsightsViewModel(
            api: activity,
            placesAPI: server,
            summaryProvider: summary
        )

        let loadTask = Task { await viewModel.load(carId: 1) }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(Set(viewModel.state.places.map(\.name)), ["Home", "Office"])
        XCTAssertNil(viewModel.state.errorMessage)
        await loadTask.value
        XCTAssertEqual(Set(viewModel.state.places.map(\.name)), ["Home", "Office"])
    }

    func testPlaceAggregationReportsMissingChargeCost() throws {
        let place = try XCTUnwrap(PlaceInsightsViewModel.aggregate([
            TeslaMateActivity(id: 2, type: "charge", startDate: "2026-07-02T08:00:00Z", startAddress: "Home", kwh: 18)
        ]).first)

        XCTAssertEqual(place.pricedChargeCount, 0)
        XCTAssertEqual(place.chargeCostIsComplete, false)
    }

    func testRepeatedEntryRestoresPlacesAndFailedRefreshPreservesThem() async {
        let cache = VehiclePageStateCache<PlaceInsightsState>()
        let key = VehiclePageCacheKey(serverURL: "https://places-cache.test", carId: 8)
        let initial = PlaceInsightsViewModel(
            api: PlaceActivityTestAPI(results: [.failure(.network("offline"))]),
            summaryProvider: StaticPlaceSummaryProvider(activities: [
                TeslaMateActivity(id: 1, type: "park", startDate: "2026-07-01T08:00:00Z", startAddress: "Home")
            ]),
            cacheKey: key,
            stateCache: cache
        )
        await initial.load(carId: 8)

        let repeated = PlaceInsightsViewModel(
            api: PlaceActivityTestAPI(results: [.failure(.network("offline"))]),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeated.state.places.map(\.name), ["Home"])
        XCTAssertFalse(repeated.state.isLoading)

        await repeated.load(carId: 8)

        XCTAssertEqual(repeated.state.places.map(\.name), ["Home"])
        XCTAssertFalse(repeated.state.isLoading)
    }

    func testConcurrentPlaceLoadsStartOneServerRefresh() async {
        let server = CountingServerPlacesTestAPI()
        let viewModel = PlaceInsightsViewModel(
            api: PlaceActivityTestAPI(results: [.failure(.network("offline"))]),
            placesAPI: server
        )

        async let first: Void = viewModel.load(carId: 9)
        async let second: Void = viewModel.load(carId: 9)
        _ = await (first, second)

        let requestCount = await server.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    private func decode(_ json: String) throws -> TeslaMateActivitiesResponse {
        try JSONDecoder.teslamate.decode(TeslaMateActivitiesResponse.self, from: Data(json.utf8))
    }

    private func decodePlaces(_ json: String) throws -> ServerPlacesResponse {
        try JSONDecoder.teslamate.decode(ServerPlacesResponse.self, from: Data(json.utf8))
    }
}

private actor StaticPlaceSettingsStore: SettingsStoring {
    private var value: AppSettings
    init(settings: AppSettings) { value = settings }
    func load() async -> AppSettings { value }
    func save(_ settings: AppSettings) async { value = settings }
}

private actor PlaceActivityTestAPI: ActivityAPIProviding {
    private var results: [APIResult<TeslaMateActivitiesResponse>]
    init(results: [APIResult<TeslaMateActivitiesResponse>]) { self.results = results }
    func activities(carId _: Int, page _: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        results.isEmpty ? .failure(.emptyBody) : results.removeFirst()
    }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> { .success([]) }
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func standbyDrain(carId _: Int, latitude _: Double, longitude _: Double) async -> APIResult<StandbyDrainResponse> { .failure(.httpStatus(404)) }
}

private actor ServerPlacesTestAPI: ServerPlacesAPIProviding {
    private var results: [APIResult<ServerPlacesResponse>]
    private(set) var requestedPages: [Int] = []
    init(results: [APIResult<ServerPlacesResponse>]) { self.results = results }
    func places(carId _: Int, page: Int, show _: Int) async -> APIResult<ServerPlacesResponse> {
        requestedPages.append(page)
        return results.isEmpty ? .failure(.emptyBody) : results.removeFirst()
    }
}

private struct StaticPlaceSummaryProvider: PlaceActivitySummaryProviding {
    let activities: [TeslaMateActivity]
    func activities(carId _: Int) async throws -> [TeslaMateActivity] { activities }
}

private actor DelayedServerPlacesTestAPI: ServerPlacesAPIProviding {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }
    func places(carId _: Int, page _: Int, show _: Int) async -> APIResult<ServerPlacesResponse> {
        try? await Task.sleep(for: delay)
        return .failure(.network("offline"))
    }
}

private actor CountingServerPlacesTestAPI: ServerPlacesAPIProviding {
    private(set) var requestCount = 0

    func places(carId _: Int, page _: Int, show _: Int) async -> APIResult<ServerPlacesResponse> {
        requestCount += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .failure(.network("offline"))
    }
}
