import XCTest
@testable import MateDroidIOS

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

        await viewModel.retryLocationEnrichment()
        XCTAssertEqual(viewModel.state.countries.first?.countryCode, "CN")
        XCTAssertEqual(viewModel.state.enrichmentResult?.failedCount, 0)
        XCTAssertEqual(viewModel.state.unclassifiedLocationCount, 0)
        let drivesRequestCount = await api.drivesRequestCount
        let enrichmentRequestCount = await enricher.requestCount
        XCTAssertEqual(drivesRequestCount, 1)
        XCTAssertEqual(enrichmentRequestCount, 2)
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

    init(drives: [DriveData]) { self.stubDrives = drives }
    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> { .failure(.httpStatus(404)) }
    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> { .failure(.httpStatus(404)) }
    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> { .failure(.httpStatus(404)) }
    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> { .success([]) }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        drivesRequestCount += 1
        return .success(stubDrives)
    }
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> { .failure(.httpStatus(404)) }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.httpStatus(404)) }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { .failure(.httpStatus(404)) }
}
