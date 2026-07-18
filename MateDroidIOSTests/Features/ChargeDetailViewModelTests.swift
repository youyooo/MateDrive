import XCTest
@testable import MateDroidIOS

@MainActor
final class ChargeDetailViewModelTests: XCTestCase {
    func testChargeDetailPresentationDistinguishesMissingEnergyFromRealZero() {
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: nil, calculatedEnergy: nil), "--")
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: 0, calculatedEnergy: nil), "0.0 kWh")
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: nil, calculatedEnergy: 12.34), "12.3 kWh")
    }

    func testChargeStatsPreserveMissingTelemetryInsteadOfInventingZeros() {
        let missing = ChargeStatsCalculator.calculateStats(ChargeDetail(chargeId: 1))

        XCTAssertNil(missing.powerMax)
        XCTAssertNil(missing.voltageMax)
        XCTAssertNil(missing.tempAvg)
        XCTAssertNil(missing.batteryStart)
        XCTAssertNil(missing.batteryEnd)
        XCTAssertNil(missing.energyAdded)
        XCTAssertNil(missing.efficiency)
        XCTAssertNil(missing.durationMin)

        let zero = ChargeStatsCalculator.calculateStats(ChargeDetail(
            chargeId: 2,
            chargeEnergyAdded: 0,
            chargeEnergyUsed: 0,
            durationMin: 0,
            batteryDetails: ChargeBatteryDetails(startBatteryLevel: 0, endBatteryLevel: 0),
            chargePoints: [ChargePoint(chargerDetails: ChargerDetails(chargerPower: 0, chargerVoltage: 0), outsideTemp: 0)]
        ))

        XCTAssertEqual(zero.powerMax, 0)
        XCTAssertEqual(zero.voltageMax, 0)
        XCTAssertEqual(zero.tempAvg, 0)
        XCTAssertEqual(zero.energyAdded, 0)
        XCTAssertEqual(zero.durationMin, 0)
    }

    func testChargeDetailLoadsAndSavesManualCostOverride() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 30,
                cost: 4
            )
        )
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [12: 6.5])
        let viewModel = ChargeDetailViewModel(api: api, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.apiCost, 4)
        XCTAssertEqual(viewModel.state.manualCost, 6.5)
        XCTAssertFalse(viewModel.state.hasPricingRules)
        XCTAssertEqual(viewModel.state.effectiveCost, 6.5)
        XCTAssertEqual(viewModel.state.costSyncState, .localOnly)

        await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: 8.25)

        XCTAssertEqual(viewModel.state.manualCost, 8.25)
        XCTAssertEqual(viewModel.state.effectiveCost, 8.25)
        XCTAssertEqual(viewModel.state.costSyncState, .localOnly)
        let fallbackUpdate = await api.latestCostUpdate()
        XCTAssertEqual(fallbackUpdate, ChargeCostUpdateCall(chargeId: 12, cost: 8.25))
        let savedCost = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertEqual(savedCost, 8.25)
    }

    func testChargeDetailSyncsManualCostToAPI26Ledger() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 30,
                cost: 4
            ),
            updateResult: .success(())
        )
        let costOverrides = InMemoryChargeCostOverrideStore()
        let viewModel = ChargeDetailViewModel(api: api, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1, chargeId: 12)
        let didSave = await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: 12.34)

        XCTAssertTrue(didSave)
        let serverUpdate = await api.latestCostUpdate()
        XCTAssertEqual(serverUpdate, ChargeCostUpdateCall(chargeId: 12, cost: 12.34))
        XCTAssertEqual(viewModel.state.apiCost, 12.34)
        XCTAssertEqual(viewModel.state.manualCost, 12.34)
        XCTAssertEqual(viewModel.state.effectiveCost, 12.34)
        XCTAssertEqual(viewModel.state.costSource, .manual)
        XCTAssertEqual(viewModel.state.costSyncState, .server)
        XCTAssertNil(viewModel.state.errorMessage)
        let savedCost = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertEqual(savedCost, 12.34)
    }

    func testChargeDetailRecognizesMatchingLocalAndAPICostAsServerSynced() async {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 30,
                cost: 12.34
            )
        )
        let viewModel = ChargeDetailViewModel(
            api: api,
            costOverrideStore: InMemoryChargeCostOverrideStore(overrides: [12: 12.34])
        )

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.costSyncState, .server)
        XCTAssertEqual(viewModel.state.effectiveCost, 12.34)
    }

    func testChargeDetailClearsServerCostAndFallsBackToPricingRule() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                address: "Mall Supercharger",
                chargeEnergyAdded: 25,
                cost: 4,
                durationMin: 30
            ),
            updateResult: .success(())
        )
        let settingsStore = StaticChargeDetailSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "supercharger",
                name: "Supercharger",
                chargeType: .dc,
                addressKeyword: "Supercharger",
                pricePerKWh: 2
            )
        ]))
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [12: 6.5])
        let viewModel = ChargeDetailViewModel(
            api: api,
            settingsStore: settingsStore,
            costOverrideStore: costOverrides
        )

        await viewModel.load(carId: 1, chargeId: 12)
        let didClear = await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: nil)

        XCTAssertTrue(didClear)
        let clearUpdate = await api.latestCostUpdate()
        XCTAssertEqual(clearUpdate, ChargeCostUpdateCall(chargeId: 12, cost: nil))
        XCTAssertNil(viewModel.state.apiCost)
        XCTAssertNil(viewModel.state.manualCost)
        XCTAssertEqual(viewModel.state.effectiveCost, 50)
        XCTAssertEqual(viewModel.state.costSource, .pricingRule)
        XCTAssertEqual(viewModel.state.costSyncState, .server)
        let savedCost = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertNil(savedCost)
    }

    func testChargeDetailParsesManualCostInputWithoutClearingOnInvalidText() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 30,
                cost: 4
            )
        )
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [12: 6.5])
        let viewModel = ChargeDetailViewModel(api: api, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1, chargeId: 12)
        let didSaveCommaValue = await viewModel.saveCostOverrideInput(carId: 1, chargeId: 12, input: "8,25")

        XCTAssertTrue(didSaveCommaValue)
        XCTAssertEqual(viewModel.state.manualCost, 8.25)
        let savedCommaCost = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertEqual(savedCommaCost, 8.25)

        let didSaveInvalidText = await viewModel.saveCostOverrideInput(carId: 1, chargeId: 12, input: "abc")

        XCTAssertFalse(didSaveInvalidText)
        XCTAssertEqual(viewModel.state.errorMessage, "Enter a valid charge cost.")
        XCTAssertEqual(viewModel.state.manualCost, 8.25)
        let savedAfterInvalidText = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertEqual(savedAfterInvalidText, 8.25)
    }

    func testChargeDetailRejectsNegativeManualCost() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 30,
                cost: 4
            )
        )
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [12: 6.5])
        let viewModel = ChargeDetailViewModel(api: api, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1, chargeId: 12)
        let didSave = await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: -1)

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.state.errorMessage, "Charge cost must be zero or greater.")
        XCTAssertEqual(viewModel.state.manualCost, 6.5)
        XCTAssertEqual(viewModel.state.effectiveCost, 6.5)
        let savedAfterNegativeCost = try await costOverrides.costOverride(carId: 1, chargeId: 12)
        XCTAssertEqual(savedAfterNegativeCost, 6.5)
    }

    func testChargeDetailUsesPositiveAPICostBeforePricingRuleAndKeepsRuleBreakdown() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                address: "Mall Supercharger",
                chargeEnergyAdded: 25,
                cost: 4,
                durationMin: 30
            )
        )
        let settingsStore = StaticChargeDetailSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "supercharger",
                name: "Supercharger",
                chargeType: .dc,
                addressKeyword: "Supercharger",
                pricePerKWh: 2
            )
        ]))
        let viewModel = ChargeDetailViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.pricingRuleCost, 50)
        XCTAssertEqual(viewModel.state.pricingRuleName, "Supercharger")
        XCTAssertTrue(viewModel.state.hasPricingRules)
        XCTAssertEqual(viewModel.state.effectiveCost, 4)
        XCTAssertEqual(viewModel.state.costSource, .api)

        await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: 12)

        XCTAssertEqual(viewModel.state.effectiveCost, 12)
        XCTAssertEqual(viewModel.state.costSource, .manual)
    }

    func testChargeDetailIgnoresZeroAPICostAndFallsBackToPricingRule() async {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                address: "Mall Supercharger",
                chargeEnergyAdded: 25,
                cost: 0,
                durationMin: 30
            )
        )
        let settingsStore = StaticChargeDetailSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "supercharger",
                name: "Supercharger",
                chargeType: .dc,
                addressKeyword: "Supercharger",
                pricePerKWh: 2
            )
        ]))
        let viewModel = ChargeDetailViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.apiCost, 0)
        XCTAssertEqual(viewModel.state.pricingRuleCost, 50)
        XCTAssertEqual(viewModel.state.effectiveCost, 50)
        XCTAssertEqual(viewModel.state.costSource, .pricingRule)
    }

    func testChargeDetailManualZeroMeansExplicitFreeAndWinsPositiveAPI() async {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 12,
                startDate: "2026-07-01T09:00:00Z",
                chargeEnergyAdded: 25,
                cost: 4
            )
        )
        let viewModel = ChargeDetailViewModel(
            api: api,
            costOverrideStore: InMemoryChargeCostOverrideStore(overrides: [12: 0])
        )

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.effectiveCost, 0)
        XCTAssertEqual(viewModel.state.costSource, .manual)
    }

    func testChargeDetailDoesNotTreatMissingPhaseSamplesAsDcEvidence() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 13,
                startDate: "2026-07-01T09:00:00Z",
                address: "Slow Public Charger",
                chargeEnergyAdded: 7,
                durationMin: 120,
                chargePoints: [
                    ChargePoint(date: "2026-07-01T09:00:00Z", chargeEnergyAdded: 0, chargerDetails: ChargerDetails(chargerPower: 3)),
                    ChargePoint(date: "2026-07-01T11:00:00Z", chargeEnergyAdded: 7, chargerDetails: ChargerDetails(chargerPower: 4))
                ]
            )
        )
        let settingsStore = StaticChargeDetailSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "dc", name: "DC", chargeType: .dc, addressKeyword: "Public", pricePerKWh: 2),
            ChargePricingRule(id: "ac", name: "AC", chargeType: .ac, addressKeyword: "Public", pricePerKWh: 0.5)
        ]))
        let viewModel = ChargeDetailViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, chargeId: 13)

        XCTAssertFalse(viewModel.state.isDcCharge)
        XCTAssertEqual(viewModel.state.pricingRuleName, "AC")
        XCTAssertEqual(viewModel.state.effectiveCost, 3.5)
    }

    func testChargeDetailTreatsZeroPhaseSamplesAsDcEvidence() async throws {
        let api = FakeChargeDetailAPI(
            detail: ChargeDetail(
                chargeId: 14,
                startDate: "2026-07-01T09:00:00Z",
                address: "Mall Supercharger",
                chargeEnergyAdded: 20,
                durationMin: 45,
                chargePoints: [
                    ChargePoint(date: "2026-07-01T09:00:00Z", chargeEnergyAdded: 0, chargerDetails: ChargerDetails(chargerPower: 80, chargerPhases: 0)),
                    ChargePoint(date: "2026-07-01T09:45:00Z", chargeEnergyAdded: 20, chargerDetails: ChargerDetails(chargerPower: 120, chargerPhases: 0))
                ]
            )
        )
        let settingsStore = StaticChargeDetailSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "dc", name: "DC", chargeType: .dc, addressKeyword: "Supercharger", pricePerKWh: 2),
            ChargePricingRule(id: "ac", name: "AC", chargeType: .ac, addressKeyword: "Supercharger", pricePerKWh: 0.5)
        ]))
        let viewModel = ChargeDetailViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1, chargeId: 14)

        XCTAssertTrue(viewModel.state.isDcCharge)
        XCTAssertEqual(viewModel.state.pricingRuleName, "DC")
        XCTAssertEqual(viewModel.state.effectiveCost, 40)
    }
}

private struct ChargeCostUpdateCall: Equatable, Sendable {
    let chargeId: Int
    let cost: Double?
}

private actor FakeChargeDetailAPI: ChargeAPIProviding {
    private let detail: ChargeDetail
    private let updateResult: APIResult<Void>
    private var costUpdates: [ChargeCostUpdateCall] = []

    init(detail: ChargeDetail, updateResult: APIResult<Void> = .failure(.httpStatus(404))) {
        self.detail = detail
        self.updateResult = updateResult
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .success(detail)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")))
    }

    func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void> {
        costUpdates.append(ChargeCostUpdateCall(chargeId: chargeId, cost: cost))
        return updateResult
    }

    func latestCostUpdate() -> ChargeCostUpdateCall? {
        costUpdates.last
    }
}

private actor InMemoryChargeCostOverrideStore: ChargeCostOverriding {
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

private struct StaticChargeDetailSettingsStore: SettingsStoring {
    let settings: AppSettings

    func load() async -> AppSettings {
        settings
    }

    func save(_: AppSettings) async {}
}
