import XCTest
@testable import MateDroidIOS

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
        XCTAssertEqual(ChargeComparisonPresentation.batteryText(start: 0, end: 0), "0% -> 0%")
    }

    func testCompareChargeSortTitlesUseChineseLanguage() {
        XCTAssertEqual(CompareChargeSort.peak.title(language: .chinese), "峰值")
        XCTAssertEqual(CompareChargeSort.duration.title(language: .chinese), "时长")
        XCTAssertEqual(CompareChargeSort.cost.title(language: .chinese), "费用")
        XCTAssertEqual(CompareChargeSort.peak.title(language: .english), "Peak")
        XCTAssertEqual(CompareChargeSort.peak.title(language: .german), "Spitzenwert")
        XCTAssertEqual(CompareChargeSort.duration.title(language: .spanish), "Duración")
        XCTAssertEqual(CompareChargeSort.cost.title(language: .italian), "Costo")
        XCTAssertEqual(CompareChargeSort.duration.title(language: .catalan), "Durada")
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
        XCTAssertEqual(viewModel.state.comparisonRows.first?.totalCost, 20)
        XCTAssertEqual(viewModel.state.comparisonRows.first?.costPerKwh, 2)
        XCTAssertEqual(viewModel.state.currencySymbol, "¥")
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
}

private final class FakeCompareChargeAPI: ChargeAPIProviding, @unchecked Sendable {
    private let details: [Int: ChargeDetail]

    init(details: [Int: ChargeDetail]) {
        self.details = details
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success(details.keys.sorted().map { ChargeData(chargeId: $0, carId: 1) })
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
