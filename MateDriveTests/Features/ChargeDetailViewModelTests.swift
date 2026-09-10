import XCTest
@testable import MateDriveApp

@MainActor
final class ChargeDetailViewModelTests: XCTestCase {
    func testChargeDetailPresentationDistinguishesMissingEnergyFromRealZero() {
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: nil, calculatedEnergy: nil), "--")
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: 0, calculatedEnergy: nil), "0.0 kWh")
        XCTAssertEqual(ChargeDetailPresentation.energyText(detailEnergy: nil, calculatedEnergy: 12.34), "12.3 kWh")
    }

    func testChargeStatsPreserveMissingTelemetryInsteadOfInventingZeros() {
        let missing = ChargingSessionAnalyzer.calculateStats(ChargeDetail(chargeId: 1))

        XCTAssertNil(missing.powerMax)
        XCTAssertNil(missing.voltageMax)
        XCTAssertNil(missing.tempAvg)
        XCTAssertNil(missing.batteryStart)
        XCTAssertNil(missing.batteryEnd)
        XCTAssertNil(missing.energyAdded)
        XCTAssertNil(missing.energyUsed)
        XCTAssertNil(missing.energyLoss)
        XCTAssertNil(missing.efficiency)
        XCTAssertNil(missing.durationMin)

        let zero = ChargingSessionAnalyzer.calculateStats(ChargeDetail(
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
        XCTAssertEqual(zero.energyUsed, 0)
        XCTAssertEqual(zero.energyLoss, 0)
        XCTAssertEqual(zero.durationMin, 0)
    }

    func testChargeStatsDoNotInventChargerInputOrPerfectEfficiency() {
        let withoutInput = ChargingSessionAnalyzer.calculateStats(ChargeDetail(chargeId: 1, chargeEnergyAdded: 20))
        XCTAssertEqual(withoutInput.energyAdded, 20)
        XCTAssertNil(withoutInput.energyUsed)
        XCTAssertNil(withoutInput.energyLoss)
        XCTAssertNil(withoutInput.efficiency)

        let measured = ChargingSessionAnalyzer.calculateStats(ChargeDetail(
            chargeId: 2,
            chargeEnergyAdded: 18,
            chargeEnergyUsed: 20
        ))
        XCTAssertEqual(measured.energyLoss, 2)
        XCTAssertEqual(try XCTUnwrap(measured.efficiency), 90, accuracy: 0.001)
    }

    func testChargeDetailAppearsBeforeSlowVehicleStatusFinishes() async {
        let api = DelayedChargeStatusAPI(detail: ChargeDetail(chargeId: 12, chargeEnergyAdded: 30))
        let viewModel = ChargeDetailViewModel(api: api)

        let loadTask = Task { await viewModel.load(carId: 1, chargeId: 12) }
        await api.waitUntilStatusRequested()
        await waitUntil { viewModel.state.chargeDetail != nil }

        XCTAssertNotNil(viewModel.state.chargeDetail)
        XCTAssertFalse(viewModel.state.isLoading)

        await api.releaseStatus()
        await loadTask.value
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func testRepeatedChargeDetailStartsWithExistingState() async {
        let cache = ChargeDetailStateCache()
        let key = ChargeDetailCacheKey(serverURL: "https://teslamate.example", carId: 1, chargeId: 12)
        let firstViewModel = ChargeDetailViewModel(
            api: FakeChargeDetailAPI(detail: ChargeDetail(chargeId: 12, address: "Cached charger", chargeEnergyAdded: 20)),
            cacheKey: key,
            stateCache: cache
        )
        await firstViewModel.load(carId: 1, chargeId: 12)

        let repeatedViewModel = ChargeDetailViewModel(
            api: FakeChargeDetailAPI(detail: ChargeDetail(chargeId: 12, address: "Fresh charger", chargeEnergyAdded: 21)),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeatedViewModel.state.chargeDetail?.address, "Cached charger")
        XCTAssertEqual(repeatedViewModel.state.stats?.energyAdded, 20)
        XCTAssertFalse(repeatedViewModel.state.isLoading)
    }

    func testChargeDetailFallsBackToPersistedSummaryWhenRawDetailIsMissing() async {
        let location = SyntheticCoordinates.point()
        let summaryCache = InMemoryChargeSummaryCache(items: [
            ChargeSummaryItem(
                chargeId: 12,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: "2026-07-01T10:00:00Z",
                chargeEnergyAdded: 18.5,
                cost: 7.25,
                durationMin: 60,
                address: "Cached charger",
                latitude: location.latitude,
                longitude: location.longitude,
                startBatteryLevel: 20,
                endBatteryLevel: 80
            )
        ])
        let viewModel = ChargeDetailViewModel(
            api: MissingChargeDetailAPI(),
            summaryCache: summaryCache
        )

        await viewModel.load(carId: 1, chargeId: 12)

        XCTAssertEqual(viewModel.state.chargeDetail?.address, "Cached charger")
        XCTAssertEqual(viewModel.state.stats?.energyAdded, 18.5)
        XCTAssertEqual(viewModel.state.stats?.batteryStart, 20)
        XCTAssertEqual(viewModel.state.stats?.batteryEnd, 80)
        XCTAssertTrue(viewModel.state.isShowingSummary)
        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.errorMessage, APIError.network("cache miss").chargeMessage)
        XCTAssertFalse(viewModel.state.isRefreshing)
    }

    func testChargeDetailShowsPersistedSummaryBeforeSlowNetworkDetailCompletes() async {
        let api = DelayedChargeDetailAPI(detail: ChargeDetail(
            chargeId: 12,
            address: "Fresh charger",
            chargeEnergyAdded: 20
        ))
        let summaryCache = InMemoryChargeSummaryCache(items: [
            ChargeSummaryItem(
                chargeId: 12,
                carId: 1,
                startDate: "2026-07-01T09:00:00Z",
                endDate: "2026-07-01T10:00:00Z",
                chargeEnergyAdded: 18.5,
                cost: 7.25,
                durationMin: 60,
                address: "Cached charger"
            )
        ])
        let viewModel = ChargeDetailViewModel(api: api, summaryCache: summaryCache)

        let loadTask = Task { await viewModel.load(carId: 1, chargeId: 12) }
        await api.waitUntilDetailRequested()
        await Task.yield()

        XCTAssertEqual(viewModel.state.chargeDetail?.address, "Cached charger")
        XCTAssertEqual(viewModel.state.stats?.energyAdded, 18.5)
        XCTAssertTrue(viewModel.state.isShowingSummary)
        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.isRefreshing)

        await api.releaseDetail()
        await loadTask.value
        XCTAssertEqual(viewModel.state.chargeDetail?.address, "Fresh charger")
        XCTAssertFalse(viewModel.state.isShowingSummary)
        XCTAssertFalse(viewModel.state.isRefreshing)
    }

    func testChargeDetailCoalescesRepeatedLoadsWhileRefreshIsInFlight() async {
        let api = DelayedChargeDetailAPI(detail: ChargeDetail(
            chargeId: 12,
            address: "Fresh charger",
            chargeEnergyAdded: 20
        ))
        let viewModel = ChargeDetailViewModel(api: api)

        let firstLoad = Task { await viewModel.load(carId: 1, chargeId: 12) }
        await api.waitUntilDetailRequested()
        let repeatedLoad = Task { await viewModel.load(carId: 1, chargeId: 12) }
        await repeatedLoad.value

        let requestCount = await api.detailRequestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(viewModel.state.isRefreshing)

        await api.releaseDetail()
        await firstLoad.value
        XCTAssertFalse(viewModel.state.isRefreshing)
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

    func testManualSaveBeforeLoadKeepsEffectiveCostAndSourceVisible() async {
        let viewModel = ChargeDetailViewModel(
            api: FakeChargeDetailAPI(detail: ChargeDetail(chargeId: 12)),
            costOverrideStore: InMemoryChargeCostOverrideStore()
        )

        let didSave = await viewModel.saveCostOverride(carId: 1, chargeId: 12, cost: 7.5)

        XCTAssertTrue(didSave)
        XCTAssertEqual(viewModel.state.manualCost, 7.5)
        XCTAssertEqual(viewModel.state.effectiveCost, 7.5)
        XCTAssertEqual(viewModel.state.costSource, .manual)
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
        XCTAssertEqual(
            viewModel.state.pricingRuleMatchFactors,
            [.savedLocation, .chargerType]
        )
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

    func testChargeDetailIgnoresForgedOfficialSettingAndUsesConfiguredCatalogEntry() async throws {
        let location = SyntheticCoordinates.point()
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/official-tariff"))
        let catalog = RegionalChargingTariffCatalog(
            version: 1,
            generatedAt: "2026-07-18",
            regions: [
                RegionalChargingTariffRegion(
                    regionCode: "CN-TEST",
                    names: ["en": "Test Region"],
                    availability: .verified,
                    verifiedAt: "2026-07-18",
                    tariffs: [
                        RegionalChargingTariff(
                            id: "catalog-rule",
                            status: .active,
                            customerClass: "residential-ev",
                            chargeType: .ac,
                            currencyCode: "CNY",
                            effectiveFromDate: "2026-01-01",
                            effectiveToDate: nil,
                            documentID: "document",
                            sourceURL: sourceURL,
                            basePricePerKWh: 0.5,
                            timeSegments: [],
                            serviceFeePerKWh: 0,
                            sessionFee: 0,
                            applicableWeekdays: nil,
                            applicableMonths: nil
                        )
                    ]
                )
            ]
        )
        let forged = ChargePricingRule(
            id: "forged",
            name: "Forged Setting",
            chargeType: .ac,
            pricePerKWh: 99,
            origin: .regionalOfficial,
            regionCode: "CN-TEST",
            sourceURL: sourceURL.absoluteString,
            verifiedAt: "2026-07-18",
            currencyCode: "CNY"
        )
        let settings = AppSettings(
            currencyCode: "CNY",
            residentialTariffRegionCode: "CN-TEST",
            appLanguage: .english,
            chargePricingRules: [forged],
            geofenceRules: [
                GeofenceRule(
                    name: "Home",
                    kind: .home,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    radiusMeters: 150
                )
            ]
        )
        let detail = ChargeDetail(
            chargeId: 18,
            startDate: "2026-07-01T10:00:00+08:00",
            address: "Home",
            chargeEnergyAdded: 10,
            cost: 0,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let viewModel = ChargeDetailViewModel(
            api: FakeChargeDetailAPI(detail: detail),
            settingsStore: StaticChargeDetailSettingsStore(settings: settings),
            regionalTariffCatalog: { catalog }
        )

        await viewModel.load(carId: 1, chargeId: 18)

        XCTAssertEqual(viewModel.state.pricingRuleName, "Test Region residential EV tariff")
        XCTAssertEqual(viewModel.state.pricingRuleCost, 5)
        XCTAssertEqual(
            viewModel.state.pricingRuleMatchFactors,
            [.regionalTariff, .chargerType, .seasonalDate]
        )
        XCTAssertEqual(viewModel.state.effectiveCost, 5)
        XCTAssertEqual(viewModel.state.costSource, .pricingRule)
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

    func testChargeDetailUsesProbableHomeRegionalEstimateAndExplainsInference() async throws {
        let detail = ChargeDetail(
            chargeId: 19,
            startDate: "2026-07-19T23:00:00+08:00",
            endDate: "2026-07-20T03:30:00+08:00",
            address: "长科路, 岳麓区, 长沙市, 湖南省",
            chargeEnergyAdded: 16.26,
            chargeEnergyUsed: 18.05,
            cost: 0,
            durationMin: 270
        )
        let viewModel = ChargeDetailViewModel(
            api: FakeChargeDetailAPI(detail: detail),
            settingsStore: StaticChargeDetailSettingsStore(
                settings: AppSettings(currencyCode: "CNY", appLanguage: .chinese)
            )
        )

        await viewModel.load(carId: 1, chargeId: 19)

        XCTAssertEqual(viewModel.state.pricingRuleCost ?? -1, 9.0972, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.effectiveCost ?? -1, 9.0972, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.costSource, .pricingRule)
        XCTAssertTrue(viewModel.state.pricingRuleMatchFactors.contains(.regionalTariff))
        XCTAssertTrue(viewModel.state.pricingRuleMatchFactors.contains(.inferredHome))
        XCTAssertTrue(viewModel.state.pricingRuleMatchFactors.contains(.historicalReference))
        XCTAssertEqual(viewModel.state.pricingRuleName, "湖南居民电动汽车历史参考电价")
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

private actor DelayedChargeStatusAPI: ChargeAPIProviding {
    private let detail: ChargeDetail
    private var statusRequested = false
    private var statusWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(detail: ChargeDetail) {
        self.detail = detail
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
        statusRequested = true
        statusWaiters.forEach { $0.resume() }
        statusWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }

    func updateChargeCost(chargeId _: Int, cost _: Double?) async -> APIResult<Void> {
        .failure(.httpStatus(404))
    }

    func waitUntilStatusRequested() async {
        guard !statusRequested else { return }
        await withCheckedContinuation { statusWaiters.append($0) }
    }

    func releaseStatus() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor DelayedChargeDetailAPI: ChargeAPIProviding {
    private let detail: ChargeDetail
    private var detailRequests = 0
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(detail: ChargeDetail) {
        self.detail = detail
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        detailRequests += 1
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success(detail)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }

    func waitUntilDetailRequested() async {
        guard detailRequests == 0 else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func detailRequestCount() -> Int {
        detailRequests
    }

    func releaseDetail() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private struct MissingChargeDetailAPI: ChargeAPIProviding {
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.network("cache miss"))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }
}

private actor InMemoryChargeSummaryCache: ChargeSummaryCaching {
    private var items: [ChargeSummaryItem]

    init(items: [ChargeSummaryItem]) {
        self.items = items
    }

    func load(carId: Int) async -> [ChargeSummaryItem] {
        items.filter { $0.carId == carId }
    }

    func save(_ items: [ChargeSummaryItem], carId _: Int) async {
        self.items = items
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
