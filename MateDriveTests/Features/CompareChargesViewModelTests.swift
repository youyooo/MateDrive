import XCTest
@testable import MateDriveApp

@MainActor
final class CompareChargesViewModelTests: XCTestCase {
    func testChargeComparisonPresentationDistinguishesMissingMetricsFromRealZero() {
        XCTAssertEqual(ChargeComparisonPresentation.powerText(nil), "--")
        XCTAssertEqual(ChargeComparisonPresentation.powerText(0), "0 kW")
        XCTAssertEqual(ChargeComparisonPresentation.durationText(nil, language: .chinese), "--")
        XCTAssertEqual(ChargeComparisonPresentation.durationText(0, language: .chinese), "0分钟")
        XCTAssertEqual(ChargeComparisonPresentation.energyText(nil), "--")
        XCTAssertEqual(ChargeComparisonPresentation.energyText(0), "0.0 kWh")
        XCTAssertEqual(ChargeComparisonPresentation.batteryText(start: nil, end: nil), "--")
        XCTAssertEqual(ChargeComparisonPresentation.batteryText(start: 0, end: 0), "0% → 0%")
    }

    func testCompareChargeSortTitlesUseChineseLanguage() {
        XCTAssertEqual(CompareChargeSort.peak.title(language: .chinese), "峰值")
        XCTAssertEqual(CompareChargeSort.duration.title(language: .chinese), "时长")
        XCTAssertEqual(CompareChargeSort.cost.title(language: .chinese), "费用")
        XCTAssertEqual(CompareChargeSort.peak.title(language: .english), "Peak")
    }

    func testChargeCurveSelectionSnapsToNearestSOCSample() throws {
        let points = [
            SessionCurvePoint(soc: 20, power: 120),
            SessionCurvePoint(soc: 40, power: 95),
            SessionCurvePoint(soc: 60, power: 70)
        ]

        XCTAssertEqual(try XCTUnwrap(ChargeCurveSelection.nearest(to: 44, in: points)), points[1])
        XCTAssertNil(ChargeCurveSelection.nearest(to: 44, in: []))
    }

    func testCompareChargesBuildsBaseRowsCurvesAndUsesManualCosts() async throws {
        let base = ChargeDetail(
            chargeId: 10,
            startDate: "2026-07-01T09:00:00Z",
            address: "Home",
            chargeEnergyAdded: 20,
            cost: 4,
            durationMin: 60,
            chargePoints: [
                .fixture(soc: 40, power: 8),
                .fixture(soc: 60, power: 11)
            ]
        )
        let comparison = ChargeDetail(
            chargeId: 11,
            startDate: "2026-07-02T09:00:00Z",
            address: "Supercharger",
            chargeEnergyAdded: 10,
            cost: 7,
            durationMin: 30,
            chargePoints: [
                .fixture(soc: 20, power: 120),
                .fixture(soc: 45, power: 96)
            ]
        )
        let api = FakeCompareChargeAPI(details: [10: base, 11: comparison])
        let overrides = InMemoryCompareChargeCostOverrideStore(overrides: [11: 3])
        let viewModel = CompareChargesViewModel(api: api, costOverrideStore: overrides)

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertEqual(viewModel.state.baseRow?.chargeId, 10)
        XCTAssertEqual(viewModel.state.comparisonRows.map(\.chargeId), [11])
        XCTAssertEqual(viewModel.state.comparisonRows.first?.totalCost, 3)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.costPerKwh, 0.3)
        XCTAssertEqual(viewModel.state.curves.map(\.chargeId).sorted(), [10, 11])
    }

    func testCompareChargesUsesPricingRulesWhenManualCostIsMissing() async throws {
        let base = ChargeDetail(
            chargeId: 10,
            startDate: "2026-07-01T09:00:00Z",
            address: "Home Garage",
            chargeEnergyAdded: 20,
            cost: nil,
            durationMin: 120
        )
        let comparison = ChargeDetail(
            chargeId: 11,
            startDate: "2026-07-02T09:00:00Z",
            address: "Mall Supercharger",
            chargeEnergyAdded: 10,
            cost: 7,
            durationMin: 30
        )
        let api = FakeCompareChargeAPI(details: [10: base, 11: comparison])
        let settingsStore = StaticCompareChargeSettingsStore(settings: AppSettings(currencyCode: "CNY", chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", chargeType: .ac, addressKeyword: "Home", pricePerKWh: 0.5),
            ChargePricingRule(id: "supercharger", name: "Supercharger", addressKeyword: "Supercharger", pricePerKWh: 2)
        ]))
        let viewModel = CompareChargesViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertEqual(viewModel.state.baseRow?.totalCost, 10)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.totalCost, 7)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.costPerKwh, 0.7)
        XCTAssertEqual(viewModel.state.currencySymbol, "¥")
    }

    func testCompareChargesUsesWallEnergyForEstimatedCostAndUnitRate() async throws {
        let base = ChargeDetail(
            chargeId: 10,
            startDate: "2026-07-01T09:00:00Z",
            address: "Home Garage",
            chargeEnergyAdded: 10,
            chargeEnergyUsed: 12,
            cost: nil,
            durationMin: 120
        )
        let api = FakeCompareChargeAPI(details: [10: base])
        let settingsStore = StaticCompareChargeSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", chargeType: .ac, addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let viewModel = CompareChargesViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertEqual(viewModel.state.baseRow?.totalCost, 6)
        XCTAssertEqual(viewModel.state.baseRow?.costPerKwh, 0.5)
        XCTAssertEqual(viewModel.state.baseRow?.energyAdded, 10)
    }

    func testCompareChargesIgnoresZeroPowerSamplesForCurves() async throws {
        let base = ChargeDetail(
            chargeId: 10,
            startDate: "2026-07-01T09:00:00Z",
            chargeEnergyAdded: 20,
            durationMin: 60,
            chargePoints: [
                .fixture(soc: 40, power: 0),
                .fixture(soc: 60, power: 0)
            ]
        )
        let comparison = ChargeDetail(
            chargeId: 11,
            startDate: "2026-07-02T09:00:00Z",
            chargeEnergyAdded: 10,
            durationMin: 30,
            chargePoints: [
                .fixture(soc: 20, power: 0),
                .fixture(soc: 45, power: 0)
            ]
        )
        let api = FakeCompareChargeAPI(details: [10: base, 11: comparison])
        let viewModel = CompareChargesViewModel(api: api)

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertTrue(viewModel.state.curves.isEmpty)
    }

    func testCompareChargesReportsMissingBaseWhenDetailIdDoesNotMatchRequestedCharge() async throws {
        let mismatchedBase = ChargeDetail(
            chargeId: 99,
            startDate: "2026-07-01T09:00:00Z",
            chargeEnergyAdded: 20,
            durationMin: 60
        )
        let api = FakeCompareChargeAPI(details: [10: mismatchedBase])
        let viewModel = CompareChargesViewModel(api: api)

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertNil(viewModel.state.baseRow)
        XCTAssertTrue(viewModel.state.rows.isEmpty)
        XCTAssertTrue(viewModel.state.curves.isEmpty)
        XCTAssertEqual(viewModel.state.errorMessage, "TeslaMate returned no charge data.")
    }

    func testCompareChargesShowsBaseBeforeSlowHistoryListFinishes() async {
        let base = ChargeDetail(chargeId: 10, chargeEnergyAdded: 20, durationMin: 60)
        let api = DelayedCompareChargeListAPI(base: base)
        let viewModel = CompareChargesViewModel(api: api)

        let loadTask = Task { await viewModel.load(carId: 1, baseChargeId: 10) }
        await api.waitUntilChargesRequested()
        for _ in 0 ..< 100 where viewModel.state.baseRow == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state.baseRow?.chargeId, 10)
        XCTAssertFalse(viewModel.state.isLoading)
        let requestedShow = await api.requestedShow
        XCTAssertEqual(requestedShow, VehicleHistoryPaginator.pageSize)

        await api.releaseCharges()
        await loadTask.value
    }

    func testCompareChargesUsesLocalChargeHistoryForCandidates() async {
        let base = ChargeDetail(chargeId: 10, chargeEnergyAdded: 20, durationMin: 60)
        let localComparison = ChargeDetail(chargeId: 12, chargeEnergyAdded: 10, durationMin: 30)
        let api = FakeCompareChargeAPI(details: [10: base, 12: localComparison])
        let viewModel = CompareChargesViewModel(
            api: api,
            historyProvider: CompareChargeHistoryProvider(
                charges: [ChargeData(chargeId: 10), ChargeData(chargeId: 12)]
            )
        )

        await viewModel.load(carId: 1, baseChargeId: 10)

        XCTAssertEqual(viewModel.state.baseRow?.chargeId, 10)
        XCTAssertEqual(viewModel.state.comparisonRows.map(\.chargeId), [12])
    }

    func testCompareChargesShowsLocalSummariesBeforeSlowDetailsFinish() async {
        let api = DelayedCompareChargeDetailAPI(details: [
            10: ChargeDetail(chargeId: 10, chargeEnergyAdded: 21, durationMin: 61),
            12: ChargeDetail(chargeId: 12, chargeEnergyAdded: 11, durationMin: 31)
        ])
        let viewModel = CompareChargesViewModel(
            api: api,
            historyProvider: CompareChargeHistoryProvider(charges: [
                ChargeData(
                    chargeId: 10,
                    startDate: "2026-07-01T09:00:00Z",
                    address: "Home",
                    chargeEnergyAdded: 20,
                    cost: 10,
                    durationMin: 60,
                    chargerPower: 11,
                    startBatteryLevel: 20,
                    endBatteryLevel: 80
                ),
                ChargeData(
                    chargeId: 12,
                    startDate: "2026-07-02T09:00:00Z",
                    address: "Office",
                    chargeEnergyAdded: 10,
                    cost: 8,
                    durationMin: 30,
                    chargerPower: 60,
                    startBatteryLevel: 30,
                    endBatteryLevel: 70
                )
            ])
        )

        let loadTask = Task { await viewModel.load(carId: 1, baseChargeId: 10) }
        await api.waitUntilDetailRequested()
        for _ in 0 ..< 100 where viewModel.state.isLoading {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.baseRow?.energyAdded, 20)
        XCTAssertEqual(viewModel.state.baseRow?.batteryStart, 20)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.chargeId, 12)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.peakKW, 60)

        await api.releaseDetails()
        await loadTask.value
        XCTAssertEqual(viewModel.state.baseRow?.energyAdded, 21)
    }

    func testCompareChargesRestoresCachedContentImmediatelyAndKeepsCurvesWhenSorting() {
        let cache = CompareChargesStateCache(maximumEntryCount: 2)
        let key = CompareChargesCacheKey(serverURL: "https://example.test", carId: 1, baseChargeId: 10)
        let cachedRow = ComparableChargeRow(
            chargeId: 10,
            isBase: true,
            startDate: "2026-07-01T09:00:00Z",
            address: "Home",
            energyAdded: 20,
            totalCost: 10,
            peakKW: 11,
            durationMin: 60,
            costPerKwh: 0.5,
            batteryStart: 20,
            batteryEnd: 80,
            isDc: false
        )
        let cachedCurve = SessionCurve(
            chargeId: 10,
            isBase: true,
            points: [
                SessionCurvePoint(soc: 20, power: 11),
                SessionCurvePoint(soc: 80, power: 8)
            ]
        )
        cache.save(
            CompareChargesState(
                isLoading: false,
                rows: [cachedRow],
                curves: [cachedCurve],
                sort: .peak,
                currencySymbol: "¥"
            ),
            for: key
        )

        let viewModel = CompareChargesViewModel(
            api: FakeCompareChargeAPI(details: [:]),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.baseRow, cachedRow)
        XCTAssertEqual(viewModel.state.curves, [cachedCurve])
        XCTAssertEqual(viewModel.state.currencySymbol, "¥")

        viewModel.setSort(.cost)

        XCTAssertEqual(viewModel.state.curves, [cachedCurve])
        XCTAssertEqual(viewModel.state.sort, .cost)
    }

    func testCompareChargesCacheDoesNotCrossServerBoundaries() {
        let cache = CompareChargesStateCache(maximumEntryCount: 2)
        cache.save(
            CompareChargesState(
                isLoading: false,
                rows: [
                    ComparableChargeRow(
                        chargeId: 10,
                        isBase: true,
                        startDate: nil,
                        address: nil,
                        energyAdded: nil,
                        totalCost: nil,
                        peakKW: nil,
                        durationMin: nil,
                        costPerKwh: nil,
                        batteryStart: nil,
                        batteryEnd: nil,
                        isDc: false
                    )
                ]
            ),
            for: CompareChargesCacheKey(
                serverURL: "https://one.example",
                carId: 1,
                baseChargeId: 10
            )
        )

        let otherServer = CompareChargesViewModel(
            api: FakeCompareChargeAPI(details: [:]),
            cacheKey: CompareChargesCacheKey(
                serverURL: "https://two.example",
                carId: 1,
                baseChargeId: 10
            ),
            stateCache: cache
        )

        XCTAssertTrue(otherServer.state.isLoading)
        XCTAssertTrue(otherServer.state.rows.isEmpty)
    }
}

private struct CompareChargeHistoryProvider: MileageDataProviding {
    let charges: [ChargeData]

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> { .success([]) }
    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> { .success(charges) }
    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> { .success(.metric) }
}

private actor DelayedCompareChargeListAPI: ChargeAPIProviding {
    private let base: ChargeDetail
    private var chargesRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedShow: Int?

    init(base: ChargeDetail) {
        self.base = base
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show: Int?) async -> APIResult<[ChargeData]> {
        requestedShow = show
        chargesRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .success(base)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }

    func waitUntilChargesRequested() async {
        guard !chargesRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseCharges() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor DelayedCompareChargeDetailAPI: ChargeAPIProviding {
    private let details: [Int: ChargeDetail]
    private var detailRequested = false
    private var detailsReleased = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(details: [Int: ChargeDetail]) {
        self.details = details
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId: Int) async -> APIResult<ChargeDetail> {
        detailRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        if !detailsReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return details[chargeId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }

    func waitUntilDetailRequested() async {
        guard !detailRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseDetails() {
        detailsReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private final class FakeCompareChargeAPI: ChargeAPIProviding, @unchecked Sendable {
    private let details: [Int: ChargeDetail]

    init(details: [Int: ChargeDetail]) {
        self.details = details
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        guard (page ?? 1) == 1 else { return .success([]) }
        return .success(details.keys.sorted().map { ChargeData(chargeId: $0, carId: 1) })
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId: Int) async -> APIResult<ChargeDetail> {
        details[chargeId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }
}

private actor InMemoryCompareChargeCostOverrideStore: ChargeCostOverriding {
    private var overrides: [Int: Double]

    init(overrides: [Int: Double] = [:]) {
        self.overrides = overrides
    }

    func costOverrides(carId _: Int) async throws -> [Int: Double] {
        overrides
    }

    func costOverride(carId _: Int, chargeId: Int) async throws -> Double? {
        overrides[chargeId]
    }

    func saveCostOverride(carId _: Int, chargeId: Int, cost: Double?) async throws {
        overrides[chargeId] = cost
    }
}

private struct StaticCompareChargeSettingsStore: SettingsStoring {
    let settings: AppSettings

    func load() async -> AppSettings {
        settings
    }

    func save(_: AppSettings) async {}
}

private extension ChargePoint {
    static func fixture(soc: Int, power: Int) -> ChargePoint {
        ChargePoint(
            batteryLevel: soc,
            chargerDetails: ChargerDetails(chargerPower: power)
        )
    }
}
