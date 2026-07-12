import XCTest
@testable import MateDroidIOS

@MainActor
final class ChargesViewModelTests: XCTestCase {
    func testChargeFiltersUseAppLanguageForDisplayTitles() {
        XCTAssertEqual(ChargeDateFilter.allTime.title(language: .chinese), "全部")
        XCTAssertEqual(ChargeDateFilter.today.title(language: .chinese), "今天")
        XCTAssertEqual(ChargeDateFilter.lastYear.title(language: .chinese), "一年")
        XCTAssertEqual(ChargeCostFilter.all.title(language: .chinese), "全部")
        XCTAssertEqual(ChargeCostFilter.hasCost.title(language: .chinese), "有费用")
        XCTAssertEqual(ChargeCostFilter.noCost.title(language: .chinese), "缺少费用")
        XCTAssertEqual(ChargeCostFilter.free.title(language: .chinese), "免费")
        XCTAssertEqual(ChargeTypeFilter.all.title(language: .chinese), "全部")
        XCTAssertEqual(ChargeTypeFilter.ac.title(language: .chinese), "交流")
        XCTAssertEqual(ChargeTypeFilter.dc.title(language: .chinese), "直流")

        XCTAssertEqual(ChargeDateFilter.allTime.title(language: .english), "All Time")
        XCTAssertEqual(ChargeCostFilter.hasCost.title(language: .english), "Has Cost")
        XCTAssertEqual(ChargeTypeFilter.all.title(language: .english), "All")
        XCTAssertEqual(ChargeDateFilter.allTime.title(language: .german), "Gesamtzeit")
        XCTAssertEqual(ChargeCostFilter.hasCost.title(language: .spanish), "Con coste")
        XCTAssertEqual(ChargeCostFilter.noCost.title(language: .german), "Fehlende Kosten")
        XCTAssertEqual(ChargeCostFilter.free.title(language: .catalan), "Gratuït")
        XCTAssertEqual(ChargeTypeFilter.all.title(language: .italian), "Tutto")
        XCTAssertEqual(ChargeDateFilter.today.title(language: .catalan), "Avui")
    }

    func testChargesViewModelHidesShortChargesWhenSettingIsOff() async throws {
        let store = InMemoryChargeSummaryStore(records: [
            .fixture(chargeId: 1, energyAdded: 0.1),
            .fixture(chargeId: 2, energyAdded: 7.4)
        ])
        let viewModel = ChargesViewModel(store: store, showShortEntries: false)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2])
        XCTAssertEqual(viewModel.state.summary.totalCharges, 1)
        XCTAssertEqual(viewModel.state.summary.totalEnergyAdded, 7.4)
    }

    func testChargeSummaryPreservesMissingEnergyAndReportsCoverage() async {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 20),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: nil)
        ])
        let viewModel = ChargesViewModel(store: store, showShortEntries: false)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2, 1])
        XCTAssertNil(viewModel.state.rows.first?.energyAdded)
        XCTAssertEqual(viewModel.state.summary.totalEnergyAdded, 20)
        XCTAssertEqual(viewModel.state.summary.energyRecordCount, 1)
        XCTAssertFalse(viewModel.state.summary.energyIsComplete)
        XCTAssertEqual(viewModel.state.summary.averageEnergyPerCharge, 20)
        XCTAssertEqual(ChargesPresentation.energyText(20, isComplete: false), "≥20.0 kWh")
        XCTAssertEqual(ChargesPresentation.energyText(nil, isComplete: false), "--")
    }

    func testChargeTypeFilterUsesAveragePowerHeuristicForUnprocessedCharges() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 4, durationMin: 120),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 30, durationMin: 30)
        ])
        let viewModel = ChargesViewModel(store: store, showShortEntries: true)

        await viewModel.load(carId: 1)
        viewModel.setTypeFilter(.dc)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2])
        XCTAssertTrue(viewModel.state.rows.first?.isDc == true)
    }

    func testCostFilterSeparatesMissingAndExplicitFreeCosts() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 4, cost: nil),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 5, cost: 0),
            ChargeSummaryItem(chargeId: 3, carId: 1, startDate: "2026-07-03T09:00:00Z", chargeEnergyAdded: 6, cost: 8.5)
        ])
        let viewModel = ChargesViewModel(store: store, showShortEntries: true)

        await viewModel.load(carId: 1)
        XCTAssertEqual(viewModel.state.summary.pricedChargeCount, 2)
        XCTAssertEqual(viewModel.state.summary.missingCostCount, 1)
        XCTAssertEqual(viewModel.state.summary.averageCostPerCharge, 4.25)
        XCTAssertEqual(
            ChargeCostCoveragePresentation.summary(viewModel.state.summary, language: .chinese),
            "覆盖 2/3 条 · 缺 1 条\n接口 2 · 规则 0 · 手动 0"
        )
        viewModel.setCostFilter(.noCost)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [1])

        viewModel.setCostFilter(.free)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2])
    }

    func testManualChargeCostOverridesAPICostInRowsSummaryAndFilters() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 20, cost: 3)
        ])
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [1: 7.5, 2: 5])
        let viewModel = ChargesViewModel(store: store, showShortEntries: true, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.cost), [5, 7.5])
        XCTAssertEqual(viewModel.state.rows.map(\.hasManualCost), [true, true])
        XCTAssertEqual(viewModel.state.summary.totalCost, 12.5)
        XCTAssertEqual(viewModel.state.summary.manualCostCount, 2)
        XCTAssertEqual(viewModel.state.summary.pricingRuleCostCount, 0)
        XCTAssertEqual(viewModel.state.summary.apiCostCount, 0)

        viewModel.setCostFilter(.hasCost)
        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2, 1])

        viewModel.setCostFilter(.noCost)
        XCTAssertTrue(viewModel.state.rows.isEmpty)
    }

    func testPricingRulesFillMissingCostsAndManualOverridesStillWin() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, durationMin: 60, address: "Home Garage"),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 20, cost: 3, durationMin: 30, address: "Mall Supercharger")
        ])
        let settingsStore = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", chargeType: .ac, addressKeyword: "Home", pricePerKWh: 0.5),
            ChargePricingRule(id: "supercharger", name: "Supercharger", chargeType: .dc, addressKeyword: "Supercharger", pricePerKWh: 2)
        ]))
        let costOverrides = InMemoryChargeCostOverrideStore(overrides: [2: 12])
        let viewModel = ChargesViewModel(store: store, settingsStore: settingsStore, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.cost), [12, 5])
        XCTAssertEqual(viewModel.state.rows.map(\.costSource), [.manual, .pricingRule])
        XCTAssertEqual(viewModel.state.summary.totalCost, 17)
    }

    func testPricingRulesUseSyncedEnergySamplesForListRowsAndSummary() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(
                chargeId: 1,
                carId: 1,
                startDate: "2026-07-01T18:30:00+08:00",
                endDate: "2026-07-01T19:30:00+08:00",
                chargeEnergyAdded: 10,
                cost: nil,
                durationMin: 60,
                address: "Third Party Station"
            )
        ])
        let settingsStore = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "third-party",
                name: "Third Party",
                addressKeyword: "Third Party",
                pricePerKWh: 9,
                timeSegments: [
                    ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                    ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
                ]
            )
        ]))
        let pricingAggregates = InMemoryChargePricingAggregateStore(aggregates: [
            1: ChargeDetailPricingAggregate(
                chargeId: 1,
                isDc: true,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T18:30:00+08:00", cumulativeEnergyAddedKWh: 0),
                    ChargePricingEnergySample(date: "2026-07-01T19:30:00+08:00", cumulativeEnergyAddedKWh: 10)
                ]
            )
        ])
        let viewModel = ChargesViewModel(
            store: store,
            settingsStore: settingsStore,
            chargePricingAggregateStore: pricingAggregates
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.first?.cost ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.rows.first?.costSource, .pricingRule)
        XCTAssertEqual(viewModel.state.summary.totalCost, 20, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.chartData.first?.totalCost ?? 0, 20, accuracy: 0.001)
    }

    func testPricingRulesUseSummaryDcFallbackWhenSyncedAggregateHasUnknownChargeType() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(
                chargeId: 1,
                carId: 1,
                startDate: "2026-07-01T09:00:00+08:00",
                endDate: "2026-07-01T09:30:00+08:00",
                chargeEnergyAdded: 25,
                cost: nil,
                durationMin: 30,
                address: "Mall Public Charger"
            ),
            ChargeSummaryItem(
                chargeId: 2,
                carId: 1,
                startDate: "2026-07-02T09:00:00+08:00",
                endDate: "2026-07-02T11:00:00+08:00",
                chargeEnergyAdded: 7,
                cost: nil,
                durationMin: 120,
                address: "Mall Public Charger"
            )
        ])
        let settingsStore = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "dc", name: "DC", chargeType: .dc, addressKeyword: "Public", pricePerKWh: 2),
            ChargePricingRule(id: "ac", name: "AC", chargeType: .ac, addressKeyword: "Public", pricePerKWh: 0.5)
        ]))
        let pricingAggregates = InMemoryChargePricingAggregateStore(aggregates: [
            1: ChargeDetailPricingAggregate(chargeId: 1, isDc: nil),
            2: ChargeDetailPricingAggregate(chargeId: 2, isDc: nil)
        ])
        let viewModel = ChargesViewModel(
            store: store,
            settingsStore: settingsStore,
            chargePricingAggregateStore: pricingAggregates
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.chargeId), [2, 1])
        XCTAssertEqual(viewModel.state.rows.map(\.isDc), [false, true])
        XCTAssertEqual(viewModel.state.rows.map(\.cost), [3.5, 50])
        XCTAssertEqual(viewModel.state.summary.totalCost, 53.5)
    }

    func testReloadCostOverridesUpdatesRowsSummaryAndFilters() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil)
        ])
        let costOverrides = InMemoryChargeCostOverrideStore()
        let viewModel = ChargesViewModel(store: store, showShortEntries: true, costOverrideStore: costOverrides)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.first?.cost, nil)
        XCTAssertEqual(viewModel.state.summary.totalCost, 0)

        try await costOverrides.saveCostOverride(carId: 1, chargeId: 1, cost: 9.25)
        await viewModel.reloadCostOverrides()

        XCTAssertEqual(viewModel.state.rows.first?.cost, 9.25)
        XCTAssertEqual(viewModel.state.rows.first?.hasManualCost, true)
        XCTAssertEqual(viewModel.state.summary.totalCost, 9.25)
    }

    func testPricingBatchPreviewSelectsMissingCostsAndProtectsExistingEvidence() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, address: "Home"),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 20, cost: 3, address: "Home"),
            ChargeSummaryItem(chargeId: 3, carId: 1, startDate: "2026-07-03T09:00:00Z", chargeEnergyAdded: 10, cost: 5, address: "Home"),
            ChargeSummaryItem(chargeId: 4, carId: 1, startDate: "2026-07-04T09:00:00Z", chargeEnergyAdded: nil, cost: nil, address: "Home"),
            ChargeSummaryItem(chargeId: 5, carId: 1, startDate: "2026-07-05T09:00:00Z", chargeEnergyAdded: nil, cost: nil, address: "Home")
        ])
        let settings = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let overrides = InMemoryChargeCostOverrideStore(overrides: [4: 8])
        let viewModel = ChargesViewModel(store: store, settingsStore: settings, costOverrideStore: overrides)

        await viewModel.load(carId: 1)
        viewModel.preparePricingBatchPreview()

        XCTAssertEqual(viewModel.state.pricingBatch.candidates.map(\.chargeId), [2, 1])
        XCTAssertEqual(viewModel.state.pricingBatch.candidates.map(\.changeKind), [.replaceRecorded, .fillMissing])
        XCTAssertEqual(viewModel.state.pricingBatch.selectedChargeIDs, [1])
        XCTAssertEqual(viewModel.state.pricingBatch.manualOverrideExcludedCount, 1)
        XCTAssertEqual(viewModel.state.pricingBatch.alreadyCorrectCount, 1)
        XCTAssertEqual(viewModel.state.pricingBatch.unmatchedCount, 1)
    }

    func testPricingBatchWritebackRecordsPartialFailureWithoutChangingFailedEvidence() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, address: "Home"),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 20, cost: 3, address: "Home")
        ])
        let settings = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let updater = BatchChargeCostUpdater(results: [
            1: [.success(())],
            2: [.failure(.httpStatus(500))]
        ])
        let viewModel = ChargesViewModel(store: store, settingsStore: settings, costUpdater: updater)

        await viewModel.load(carId: 1)
        viewModel.preparePricingBatchPreview()
        viewModel.setPricingBatchSelection(chargeId: 2, isSelected: true)
        await viewModel.applyPricingBatch()

        let receipt = try XCTUnwrap(viewModel.state.pricingBatch.lastReceipt)
        XCTAssertEqual(receipt.results.filter(\.succeeded).map(\.chargeId), [1])
        XCTAssertEqual(receipt.results.filter { !$0.succeeded }.map(\.chargeId), [2])
        XCTAssertEqual(receipt.results.first { $0.chargeId == 1 }?.previousCost, nil)
        XCTAssertEqual(receipt.results.first { $0.chargeId == 1 }?.newCost, 5)
        XCTAssertEqual(receipt.results.first { $0.chargeId == 2 }?.previousCost, 3)
        XCTAssertEqual(receipt.results.first { $0.chargeId == 2 }?.newCost, 10)
        XCTAssertTrue(receipt.results.first { $0.chargeId == 2 }?.message?.contains("500") == true)
        XCTAssertEqual(viewModel.state.pricingBatch.selectedChargeIDs, [2])
        let calls = await updater.calls()
        XCTAssertEqual(calls, [
            BatchChargeCostUpdateCall(chargeId: 2, cost: 10),
            BatchChargeCostUpdateCall(chargeId: 1, cost: 5)
        ])
    }

    func testPricingBatchRollbackRestoresOriginalAPICost() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, address: "Home")
        ])
        let settings = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let updater = BatchChargeCostUpdater(results: [1: [.success(()), .success(())]])
        let viewModel = ChargesViewModel(store: store, settingsStore: settings, costUpdater: updater)

        await viewModel.load(carId: 1)
        viewModel.preparePricingBatchPreview()
        await viewModel.applyPricingBatch()
        await viewModel.rollbackLastPricingBatch()

        let receipt = try XCTUnwrap(viewModel.state.pricingBatch.lastReceipt)
        XCTAssertEqual(receipt.rollbackResults?.map(\.succeeded), [true])
        let calls = await updater.calls()
        XCTAssertEqual(calls, [
            BatchChargeCostUpdateCall(chargeId: 1, cost: 5),
            BatchChargeCostUpdateCall(chargeId: 1, cost: nil)
        ])
    }

    func testPricingBatchPersistsVehicleScopedAuditAndUpdatesItAfterRollback() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 7, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, address: "Home")
        ])
        let settings = StaticChargesSettingsStore(settings: AppSettings(currencyCode: "CNY", chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home weekday", addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let updater = BatchChargeCostUpdater(results: [1: [.success(()), .success(())]])
        let auditStore = InMemoryChargePricingAuditStore()
        let viewModel = ChargesViewModel(
            store: store,
            settingsStore: settings,
            costUpdater: updater,
            pricingAuditStore: auditStore
        )

        await viewModel.load(carId: 7)
        viewModel.preparePricingBatchPreview()
        await viewModel.applyPricingBatch()

        let writeRecord = try XCTUnwrap(viewModel.state.pricingBatch.auditHistory.first)
        XCTAssertEqual(writeRecord.carId, 7)
        XCTAssertEqual(writeRecord.currencyCode, "CNY")
        XCTAssertEqual(writeRecord.receipt.results.first?.startDate, "2026-07-01T09:00:00Z")
        XCTAssertEqual(writeRecord.receipt.results.first?.ruleID, "home")
        XCTAssertEqual(writeRecord.receipt.results.first?.ruleName, "Home weekday")

        await viewModel.rollbackLastPricingBatch()

        let rollbackRecord = try XCTUnwrap(viewModel.state.pricingBatch.auditHistory.first)
        XCTAssertEqual(rollbackRecord.id, writeRecord.id)
        XCTAssertEqual(rollbackRecord.receipt.rollbackResults?.map(\.succeeded), [true])
        let persisted = try await auditStore.records(carId: 7, limit: 20)
        let otherVehicleRecords = try await auditStore.records(carId: 8, limit: 20)
        XCTAssertEqual(persisted, [rollbackRecord])
        XCTAssertTrue(otherVehicleRecords.isEmpty)
    }

    func testPricingBatchKeepsExplicitlyDeselectedMissingCostAfterAnotherWrite() async throws {
        let store = InMemoryChargeSummaryStore(items: [
            ChargeSummaryItem(chargeId: 1, carId: 1, startDate: "2026-07-01T09:00:00Z", chargeEnergyAdded: 10, cost: nil, address: "Home"),
            ChargeSummaryItem(chargeId: 2, carId: 1, startDate: "2026-07-02T09:00:00Z", chargeEnergyAdded: 20, cost: nil, address: "Home")
        ])
        let settings = StaticChargesSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", addressKeyword: "Home", pricePerKWh: 0.5)
        ]))
        let updater = BatchChargeCostUpdater(results: [2: [.success(())]])
        let viewModel = ChargesViewModel(store: store, settingsStore: settings, costUpdater: updater)

        await viewModel.load(carId: 1)
        viewModel.preparePricingBatchPreview()
        viewModel.setPricingBatchSelection(chargeId: 1, isSelected: false)
        await viewModel.applyPricingBatch()

        XCTAssertEqual(viewModel.state.pricingBatch.candidates.map(\.chargeId), [1])
        XCTAssertTrue(viewModel.state.pricingBatch.selectedChargeIDs.isEmpty)
    }
}

private struct BatchChargeCostUpdateCall: Equatable, Sendable {
    let chargeId: Int
    let cost: Double?
}

private actor BatchChargeCostUpdater: ChargeCostUpdating {
    private var results: [Int: [APIResult<Void>]]
    private var recordedCalls: [BatchChargeCostUpdateCall] = []

    init(results: [Int: [APIResult<Void>]]) {
        self.results = results
    }

    func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void> {
        recordedCalls.append(BatchChargeCostUpdateCall(chargeId: chargeId, cost: cost))
        guard var values = results[chargeId], !values.isEmpty else { return .failure(.emptyBody) }
        let result = values.removeFirst()
        results[chargeId] = values
        return result
    }

    func calls() -> [BatchChargeCostUpdateCall] {
        recordedCalls
    }
}

private actor InMemoryChargePricingAuditStore: ChargePricingAuditStoring {
    private var savedRecords: [String: ChargePricingAuditRecord] = [:]

    func save(carId: Int, currencyCode: String, receipt: ChargePricingBatchReceipt) async throws {
        savedRecords[receipt.id] = ChargePricingAuditRecord(carId: carId, currencyCode: currencyCode, receipt: receipt)
    }

    func records(carId: Int, limit: Int) async throws -> [ChargePricingAuditRecord] {
        Array(savedRecords.values.filter { $0.carId == carId }.sorted { $0.receipt.createdAt > $1.receipt.createdAt }.prefix(limit))
    }
}

private final class InMemoryChargeSummaryStore: ChargeSummaryProviding, @unchecked Sendable {
    private let items: [ChargeSummaryItem]

    init(records: [ChargeSummaryRecord]) {
        self.items = records.map(ChargeSummaryItem.init(record:))
    }

    init(items: [ChargeSummaryItem]) {
        self.items = items
    }

    func chargeSummaries(carId: Int) async -> APIResult<[ChargeSummaryItem]> {
        .success(items.filter { $0.carId == carId })
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

private struct StaticChargesSettingsStore: SettingsStoring {
    let settings: AppSettings

    func load() async -> AppSettings {
        settings
    }

    func save(_: AppSettings) async {}
}

private struct InMemoryChargePricingAggregateStore: ChargePricingAggregateProviding {
    let aggregates: [Int: ChargeDetailPricingAggregate]

    func chargePricingAggregates(carId _: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        aggregates
    }
}

private extension ChargeSummaryRecord {
    static func fixture(chargeId: Int, energyAdded: Double) -> ChargeSummaryRecord {
        ChargeSummaryRecord(
            chargeId: chargeId,
            carId: 1,
            startDate: "2026-07-0\(chargeId)T09:00:00Z",
            endDate: nil,
            chargeEnergyAdded: energyAdded,
            cost: nil
        )
    }
}
