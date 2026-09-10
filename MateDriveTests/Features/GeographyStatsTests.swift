import XCTest
@testable import MateDriveApp

@MainActor
final class GeographyStatsTests: XCTestCase {
    func testCountryResolverUsesRealISOCodeForEnglishAndChineseNames() {
        XCTAssertEqual(CountryISOResolver.resolve("Germany")?.code, "DE")
        XCTAssertEqual(CountryISOResolver.resolve("中国")?.code, "CN")
        XCTAssertEqual(CountryISOResolver.resolve("us")?.code, "US")
    }

    func testDistrictOnlyTeslaMateAddressIsNotMisreportedAsCountry() {
        XCTAssertNil(CountryISOResolver.resolve("岳麓区"))
        let drives = [DriveData(
            driveId: 1,
            startDate: "2026-07-11T07:40:59+08:00",
            endDate: "2026-07-11T09:36:18+08:00",
            distance: 60.88,
            startAddress: "长科路, 岳麓区",
            endAddress: "长科路, 岳麓区"
        )]

        XCTAssertTrue(CountriesVisitedViewModel.aggregate(drives: drives, charges: [], year: nil).isEmpty)
        XCTAssertEqual(CountriesVisitedViewModel.unclassifiedCount(drives: drives, charges: [], year: nil), 1)
    }

    func testCountryAggregationGroupsAliasesByISOCode() {
        let drives = [
            DriveData(driveId: 1, startDate: "2026-01-01T08:00:00Z", distance: 10, endAddress: "Berlin, Germany"),
            DriveData(driveId: 2, startDate: "2026-01-02T08:00:00Z", distance: 20, endAddress: "Hamburg, DE")
        ]

        let countries = CountriesVisitedViewModel.aggregate(drives: drives, charges: [], year: nil)

        XCTAssertEqual(countries.count, 1)
        XCTAssertEqual(countries.first?.countryCode, "DE")
        XCTAssertEqual(countries.first?.driveCount, 2)
        XCTAssertEqual(countries.first?.totalDistanceKm, 30)
    }

    func testCountryAndRegionAggregationReportMissingDistanceAndEnergyCoverage() throws {
        let drives = [
            DriveData(driveId: 1, startDate: "2026-01-01T08:00:00Z", distance: 10, endAddress: "Munich, Bavaria, Germany"),
            DriveData(driveId: 2, startDate: "2026-01-02T08:00:00Z", distance: nil, endAddress: "Nuremberg, Bavaria, Germany")
        ]
        let charges = [
            ChargeData(chargeId: 1, startDate: "2026-01-01T10:00:00Z", address: "Munich, Bavaria, Germany", chargeEnergyAdded: 20),
            ChargeData(chargeId: 2, startDate: "2026-01-02T10:00:00Z", address: "Nuremberg, Bavaria, Germany", chargeEnergyAdded: nil)
        ]

        let country = try XCTUnwrap(CountriesVisitedViewModel.aggregate(drives: drives, charges: charges, year: nil).first)
        let region = try XCTUnwrap(RegionsVisitedViewModel.aggregate(drives: drives, charges: charges, countryName: "Germany", year: nil).first)

        XCTAssertEqual(country.totalDistanceKm, 10)
        XCTAssertEqual(country.totalChargeEnergyKwh, 20)
        XCTAssertEqual(country.missingDriveDistanceCount, 1)
        XCTAssertEqual(country.missingChargeEnergyCount, 1)
        XCTAssertEqual(region.missingDriveDistanceCount, 1)
        XCTAssertEqual(region.missingChargeEnergyCount, 1)
        XCTAssertEqual(GeographyCoveragePresentation.valuePrefix(missingCount: 1), "≥")
    }

    func testResolvedGeographyCompletesCountryAndRegionForDistrictOnlyAddress() {
        let address = "长科路, 岳麓区"
        let drives = [DriveData(driveId: 1, startDate: "2026-07-11T07:40:59+08:00", distance: 60.88, endAddress: address)]
        let resolved = [address: GeocodedLocation(countryCode: "CN", countryName: "中国", regionName: "湖南省", city: "长沙市")]

        let countries = CountriesVisitedViewModel.aggregate(drives: drives, charges: [], year: nil, resolvedLocations: resolved)
        let regions = RegionsVisitedViewModel.aggregate(drives: drives, charges: [], countryName: "中国", year: nil, resolvedLocations: resolved)

        XCTAssertEqual(countries.first?.countryCode, "CN")
        XCTAssertEqual(countries.first?.countryName, "中国")
        XCTAssertEqual(regions.first?.regionName, "湖南省")
        XCTAssertEqual(CountriesVisitedViewModel.unclassifiedCount(drives: drives, charges: [], year: nil, resolvedLocations: resolved), 0)
    }

    func testCountryViewModelRetriesEnrichmentWithoutReloadingSummaries() async {
        let address = "长科路, 岳麓区"
        let drive = DriveData(driveId: 1, startDate: "2026-07-11T07:40:59+08:00", distance: 60.88, endAddress: address)
        let api = GeographyAnalyticsAPI(drives: [drive])
        let enricher = SequencedGeographyEnricher(results: [
            GeographyEnrichmentResult(locations: [:], candidateCount: 1, cachedCount: 0, requestedCount: 1, failedCount: 1),
            GeographyEnrichmentResult(locations: [address: GeocodedLocation(countryCode: "CN", countryName: "中国", regionName: "湖南省")], candidateCount: 1, cachedCount: 0, requestedCount: 1, failedCount: 0)
        ])
        let viewModel = CountriesVisitedViewModel(api: api, geographyEnricher: enricher)

        await viewModel.load(carId: 1, year: nil)
        XCTAssertEqual(viewModel.state.enrichmentResult?.failedCount, 1)
        XCTAssertEqual(viewModel.state.unclassifiedLocationCount, 1)
        let requestsAfterInitialLoad = await api.drivesRequestCount

        await viewModel.retryLocationEnrichment()
        XCTAssertEqual(viewModel.state.countries.first?.countryCode, "CN")
        XCTAssertEqual(viewModel.state.enrichmentResult?.failedCount, 0)
        XCTAssertEqual(viewModel.state.unclassifiedLocationCount, 0)
        let drivesRequestCount = await api.drivesRequestCount
        let enrichmentRequestCount = await enricher.requestCount
        XCTAssertEqual(drivesRequestCount, requestsAfterInitialLoad)
        XCTAssertEqual(enrichmentRequestCount, 2)
    }

    func testCountryAndRegionViewModelsUseLocalHistoryWithoutRequestingLargeAPIPages() async {
        let drive = DriveData(
            driveId: 1,
            startDate: "2026-07-11T07:40:59+08:00",
            distance: 60.88,
            endAddress: "长沙市, 湖南省, 中国"
        )
        let charge = ChargeData(
            chargeId: 2,
            startDate: "2026-07-11T10:00:00+08:00",
            address: "长沙市, 湖南省, 中国",
            chargeEnergyAdded: 20
        )
        let api = GeographyAnalyticsAPI(drives: [])
        let provider = GeographyHistoryProvider(drives: [drive], charges: [charge])
        let countries = CountriesVisitedViewModel(api: api, historyProvider: provider)
        let regions = RegionsVisitedViewModel(api: api, historyProvider: provider)

        await countries.load(carId: 1, year: 2026)
        let countryName = try? XCTUnwrap(countries.state.countries.first?.countryName)
        await regions.load(carId: 1, countryName: countryName ?? "China", year: 2026)

        XCTAssertEqual(countries.state.countries.first?.countryCode, "CN")
        XCTAssertEqual(countries.state.countries.first?.driveCount, 1)
        XCTAssertEqual(countries.state.countries.first?.chargeCount, 1)
        XCTAssertEqual(regions.state.regions.first?.regionName, "湖南省")
        let drivesRequestCount = await api.drivesRequestCount
        XCTAssertEqual(drivesRequestCount, 0)
    }

    func testCountryRepeatedEntryRestoresScopedStateAndPreservesItOnFailure() async {
        let drive = DriveData(
            driveId: 1,
            startDate: "2026-07-11T07:40:59+08:00",
            distance: 60.88,
            endAddress: "长沙市, 湖南省, 中国"
        )
        let cache = VehiclePageStateCache<CountriesVisitedState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://example.invalid",
            carId: 1,
            scope: "countries:2026"
        )
        let first = CountriesVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: GeographyHistoryProvider(drives: [drive], charges: []),
            cacheKey: key,
            stateCache: cache
        )
        await first.load(carId: 1, year: 2026)
        first.setSortOrder(.distance)

        let reopened = CountriesVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: FailingGeographyHistoryProvider(),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.countries.first?.countryCode, "CN")
        XCTAssertEqual(reopened.state.sortOrder, .distance)

        await reopened.load(carId: 1, year: 2026)

        XCTAssertEqual(reopened.state.countries.first?.countryCode, "CN")
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertFalse(reopened.state.isRefreshing)
    }

    func testRegionRepeatedEntryRestoresScopedStateAndPreservesItOnFailure() async {
        let drive = DriveData(
            driveId: 1,
            startDate: "2026-07-11T07:40:59+08:00",
            distance: 60.88,
            endAddress: "长沙市, 湖南省, 中国"
        )
        let cache = VehiclePageStateCache<RegionsVisitedState>()
        let countryName = CountriesVisitedViewModel.country(from: drive.endAddress)?.name ?? "China"
        let key = VehiclePageCacheKey(
            serverURL: "https://example.invalid",
            carId: 1,
            scope: "regions:cn:2026"
        )
        let first = RegionsVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: GeographyHistoryProvider(drives: [drive], charges: []),
            cacheKey: key,
            stateCache: cache
        )
        await first.load(carId: 1, countryName: countryName, year: 2026)
        first.setSortOrder(.distance)

        let reopened = RegionsVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: FailingGeographyHistoryProvider(),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.regions.first?.regionName, "湖南省")
        XCTAssertEqual(reopened.state.sortOrder, .distance)

        await reopened.load(carId: 1, countryName: countryName, year: 2026)

        XCTAssertEqual(reopened.state.regions.first?.regionName, "湖南省")
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertFalse(reopened.state.isRefreshing)
    }

    func testCountryAndRegionConcurrentLoadsEachReadHistoryOnce() async {
        let drive = DriveData(
            driveId: 1,
            startDate: "2026-07-11T07:40:59+08:00",
            distance: 60.88,
            endAddress: "长沙市, 湖南省, 中国"
        )
        let countryProvider = SlowGeographyHistoryProvider(drives: [drive], charges: [])
        let countries = CountriesVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: countryProvider
        )

        async let firstCountry: Void = countries.load(carId: 1, year: 2026)
        async let secondCountry: Void = countries.load(carId: 1, year: 2026)
        _ = await (firstCountry, secondCountry)

        let countryDriveReads = await countryProvider.driveReadCount
        XCTAssertEqual(countryDriveReads, 1)

        let regionProvider = SlowGeographyHistoryProvider(drives: [drive], charges: [])
        let countryName = CountriesVisitedViewModel.country(from: drive.endAddress)?.name ?? "China"
        let regions = RegionsVisitedViewModel(
            api: GeographyAnalyticsAPI(drives: []),
            historyProvider: regionProvider
        )

        async let firstRegion: Void = regions.load(carId: 1, countryName: countryName, year: 2026)
        async let secondRegion: Void = regions.load(carId: 1, countryName: countryName, year: 2026)
        _ = await (firstRegion, secondRegion)

        let regionDriveReads = await regionProvider.driveReadCount
        XCTAssertEqual(regionDriveReads, 1)
    }

    func testHistoricalGeographyEnrichmentBoundsFailedDetailRequests() async {
        let charges = (1 ... 10).map { (id: Int) in
            ChargeData(chargeId: id, address: "Unknown district \(id)")
        }
        let api = GeographyAnalyticsAPI(drives: [])
        let enricher = HistoricalGeographyEnricher(
            api: api,
            geocoder: GeocodingService(queueStore: EmptyGeocodeQueueStore()),
            maximumAddresses: 0,
            maximumCandidates: 100,
            maximumDetailRequests: 3
        )

        let result = await enricher.resolveUnknownLocations(carId: 1, drives: [], charges: charges)

        XCTAssertTrue(result.locations.isEmpty)
        let detailRequestCount = await api.chargeDetailRequestCount
        XCTAssertEqual(detailRequestCount, 3)
    }
}

private struct GeographyHistoryProvider: MileageDataProviding {
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

private struct FailingGeographyHistoryProvider: MileageDataProviding {
    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        .failure(.network("offline"))
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        .failure(.network("offline"))
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .failure(.network("offline"))
    }
}

private actor SlowGeographyHistoryProvider: MileageDataProviding {
    let drives: [DriveData]
    let charges: [ChargeData]
    private(set) var driveReadCount = 0

    init(drives: [DriveData], charges: [ChargeData]) {
        self.drives = drives
        self.charges = charges
    }

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        driveReadCount += 1
        try? await Task.sleep(for: .milliseconds(50))
        return .success(drives)
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        try? await Task.sleep(for: .milliseconds(50))
        return .success(charges)
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        try? await Task.sleep(for: .milliseconds(50))
        return .success(UnitPreferences(unitOfLength: "km"))
    }
}

private actor SequencedGeographyEnricher: HistoricalGeographyEnriching {
    private var results: [GeographyEnrichmentResult]
    private(set) var requestCount = 0

    init(results: [GeographyEnrichmentResult]) { self.results = results }

    func resolveUnknownLocations(carId _: Int, drives _: [DriveData], charges _: [ChargeData]) async -> GeographyEnrichmentResult {
        requestCount += 1
        return results.isEmpty ? GeographyEnrichmentResult(locations: [:], candidateCount: 0, cachedCount: 0, requestedCount: 0, failedCount: 0) : results.removeFirst()
    }
}

private actor GeographyAnalyticsAPI: AnalyticsAPIProviding {
    let stubDrives: [DriveData]
    private(set) var drivesRequestCount = 0
    private(set) var chargeDetailRequestCount = 0

    init(drives: [DriveData]) { self.stubDrives = drives }
    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> { .failure(.httpStatus(404)) }
    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> { .failure(.httpStatus(404)) }
    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> { .failure(.httpStatus(404)) }
    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> { .success([]) }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        drivesRequestCount += 1
        return (page ?? 1) == 1 ? .success(stubDrives) : .success([])
    }
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> { .failure(.httpStatus(404)) }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        chargeDetailRequestCount += 1
        return .failure(.httpStatus(404))
    }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { .failure(.httpStatus(404)) }
}

private struct EmptyGeocodeQueueStore: GeocodeQueueStoring {
    func cachedLocation(gridLatitude _: Int, gridLongitude _: Int) async throws -> GeocodedLocation? { nil }
    func enqueue(_: [GeocodeQueueItem]) async throws {}
    func save(location _: GeocodedLocation, latitude _: Double, longitude _: Double) async throws {}
    func pending(limit _: Int) async throws -> [GeocodeQueueItem] { [] }
    func removePending(gridLatitude _: Int, gridLongitude _: Int) async throws {}
}
