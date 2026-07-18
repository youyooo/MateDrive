import XCTest
@testable import MateDroidIOS

final class ChargeCostResolverTests: XCTestCase {
    func testManualZeroMeansExplicitFreeAndWinsEverySource() {
        let pricingInput = ChargePricingInput(
            startDate: "2026-07-01T09:00:00+08:00",
            address: "Home",
            latitude: nil,
            longitude: nil,
            energyAddedKWh: 10,
            isDc: false
        )
        let result = ChargeCostResolver.resolve(ChargeCostResolutionInput(
            manualCost: 0,
            apiCost: 25,
            currencyCode: "CNY",
            isAC: true,
            geofenceKind: .home,
            pricingInput: pricingInput,
            rules: [
                ChargePricingRule(
                    id: "station",
                    name: "Station",
                    pricePerKWh: 1,
                    origin: .stationLearned
                )
            ],
            regionalRule: ChargePricingRule(
                id: "regional",
                name: "Regional",
                chargeType: .ac,
                pricePerKWh: 0.5,
                origin: .regionalOfficial
            )
        ))

        XCTAssertEqual(result?.amount, 0)
        XCTAssertEqual(result?.source, .manual)
        XCTAssertTrue(result?.isExplicitlyFree == true)
    }

    func testPositiveAPICostWinsRuleEstimates() {
        let result = ChargeCostResolver.resolve(makeInput(
            apiCost: 25,
            rules: [stationRule(price: 1)]
        ))

        XCTAssertEqual(result?.amount, 25)
        XCTAssertEqual(result?.source, .api)
        XCTAssertFalse(result?.isEstimated == true)
    }

    func testRegionalTariffNeverAppliesOutsideConfirmedHomeAC() {
        let dcResult = ChargeCostResolver.resolve(makeInput(
            isAC: false,
            geofenceKind: .charging,
            pricingInput: pricingInput(isDc: true),
            regionalRule: regionalRule(price: 0.5)
        ))
        let nonHomeResult = ChargeCostResolver.resolve(makeInput(
            isAC: true,
            geofenceKind: .charging,
            regionalRule: regionalRule(price: 0.5)
        ))

        XCTAssertNil(dcResult)
        XCTAssertNil(nonHomeResult)
    }

    func testConfirmedStationRuleWinsRegionalHomeFallbackAndZeroAPIIsIgnored() {
        let result = ChargeCostResolver.resolve(makeInput(
            apiCost: 0,
            geofenceKind: .home,
            rules: [stationRule(price: 0.66)],
            regionalRule: regionalRule(price: 0.5)
        ))

        XCTAssertEqual(result?.source, .stationRule)
        XCTAssertEqual(result?.unitPricePerKWh, 0.66)
        XCTAssertEqual(result?.amount, 6.6)
    }

    func testRuleResolutionAddsServiceAndFixedFeesWithoutParkingCost() {
        let rule = ChargePricingRule(
            id: "fees",
            name: "Fees",
            pricePerKWh: 0.5,
            sessionFee: 1,
            origin: .stationLearned,
            serviceFeePerKWh: 0.2,
            parkingFeeRuleID: "parking-1"
        )

        let result = ChargeCostResolver.resolve(makeInput(rules: [rule]))

        XCTAssertEqual(result?.amount, 8)
        XCTAssertEqual(result?.unitPricePerKWh, 0.5)
        XCTAssertEqual(result?.serviceFee, 2)
        XCTAssertEqual(result?.sessionFee, 1)
        XCTAssertEqual(result?.parkingFeeRuleID, "parking-1")
        XCTAssertEqual(result?.components.reduce(0) { $0 + $1.cost }, 5)
    }

    func testUserRuleWinsLearnedRuleAtEqualPriority() {
        let learned = stationRule(id: "learned", price: 0.8, priority: 100)
        let user = ChargePricingRule(
            id: "user",
            name: "User",
            pricePerKWh: 0.7,
            priority: 100,
            origin: .user
        )

        let result = ChargeCostResolver.resolve(makeInput(rules: [learned, user]))

        XCTAssertEqual(result?.ruleID, "user")
    }

    func testMatchingWeekdayAndMonthRuleSegmentsEnergyAcrossMidnight() {
        let rule = ChargePricingRule(
            id: "overnight-summer",
            name: "Overnight Summer",
            pricePerKWh: 9,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: 23 * 60,
                    endMinuteOfDay: 23 * 60 + 59,
                    pricePerKWh: 2
                ),
                ChargePricingTimeSegment(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 7 * 60,
                    pricePerKWh: 0.5
                )
            ],
            sessionFee: 1,
            origin: .stationLearned,
            serviceFeePerKWh: 0.1,
            applicableWeekdays: [4],
            applicableMonths: [7]
        )
        let pricingInput = ChargePricingInput(
            startDate: "2026-07-01T23:00:00+08:00",
            endDate: "2026-07-02T01:00:00+08:00",
            address: nil,
            latitude: nil,
            longitude: nil,
            energyAddedKWh: 20,
            isDc: false
        )

        let result = ChargeCostResolver.resolve(makeInput(
            pricingInput: pricingInput,
            rules: [rule]
        ))

        XCTAssertEqual(result?.amount ?? 0, 28, accuracy: 0.001)
        XCTAssertEqual(result?.unitPricePerKWh ?? 0, 1.25, accuracy: 0.001)
        XCTAssertEqual(result?.serviceFee, 2)
        XCTAssertEqual(result?.components.count, 2)
    }

    func testExpiredOrCurrencyMismatchedRegionalTariffIsRejected() {
        let expired = ChargePricingRule(
            id: "expired",
            name: "Expired",
            chargeType: .ac,
            effectiveToDate: "2026-06-30",
            pricePerKWh: 0.5,
            origin: .regionalOfficial,
            regionCode: "CN-43",
            sourceURL: "https://example.com/tariff",
            verifiedAt: "2026-07-18",
            currencyCode: "CNY"
        )

        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            currencyCode: "CNY",
            geofenceKind: .home,
            regionalRule: expired
        )))
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            currencyCode: "USD",
            geofenceKind: .home,
            regionalRule: regionalRule(price: 0.5)
        )))
    }

    func testExplicitWrongCurrencyRuleIsRejectedWhileLegacyRuleCanUseSelectedCurrency() {
        let wrongCurrency = ChargePricingRule(
            id: "usd",
            name: "USD",
            pricePerKWh: 0.1,
            priority: 200,
            currencyCode: "usd"
        )
        let legacy = ChargePricingRule(
            id: "legacy",
            name: "Legacy",
            pricePerKWh: 0.5
        )

        let result = ChargeCostResolver.resolve(makeInput(
            currencyCode: "CNY",
            rules: [wrongCurrency, legacy]
        ))

        XCTAssertEqual(wrongCurrency.currencyCode, "USD")
        XCTAssertEqual(result?.ruleID, "legacy")
        XCTAssertEqual(result?.currencyCode, "CNY")
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            currencyCode: "CNY",
            rules: [wrongCurrency]
        )))
    }

    func testLegacyCurrencyOnlyMatchesUserRules() {
        let legacyUser = ChargePricingRule(
            id: "legacy-user",
            name: "Legacy User",
            pricePerKWh: 0.5
        )
        let legacyStation = stationRule(id: "legacy-station", price: 0.8)
        var blankLegacyStation = stationRule(id: "blank-legacy-station", price: 0.9)
        blankLegacyStation.currencyCode = "   "

        XCTAssertEqual(
            ChargeCostResolver.resolve(makeInput(rules: [legacyUser]))?.ruleID,
            legacyUser.id
        )
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(rules: [legacyStation])))
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(rules: [blankLegacyStation])))
    }

    func testRegionalFallbackRequiresCompleteCatalogProvenance() {
        var forged = regionalRule(price: 0.5)
        forged.sourceURL = nil
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            geofenceKind: .home,
            regionalRule: forged
        )))

        forged = regionalRule(price: 0.5)
        forged.verifiedAt = nil
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            geofenceKind: .home,
            regionalRule: forged
        )))

        forged = regionalRule(price: 0.5)
        forged.currencyCode = "USD"
        XCTAssertNil(ChargeCostResolver.resolve(makeInput(
            geofenceKind: .home,
            regionalRule: forged
        )))
    }

    func testSessionOnlyConfirmationSavesManualCostAndObservationWithoutRule() async throws {
        let existingRule = ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.4)
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let settings = ResolverTestSettingsStore(AppSettings(chargePricingRules: [existingRule]))
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        try await service.confirm(ChargePricingConfirmation(
            carId: 1,
            chargeId: 10,
            stationKey: "geofence:home",
            scope: .sessionOnly,
            finalAmount: 0,
            billedEnergyKWh: 0,
            pricePerKWh: nil,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: "CNY",
            coordinates: GeocodeLocation(latitude: 31.2304, longitude: 121.4737),
            chargerIdentity: .ac,
            startMinute: nil,
            endMinute: nil
        ))
        try await service.confirm(ChargePricingConfirmation(
            carId: 1,
            chargeId: 12,
            stationKey: "geofence:home",
            scope: .sessionOnly,
            finalAmount: 5,
            billedEnergyKWh: nil,
            pricePerKWh: nil,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: "CNY",
            coordinates: nil,
            chargerIdentity: .ac,
            startMinute: nil,
            endMinute: nil
        ))

        let savedOverride = try await overrides.costOverride(carId: 1, chargeId: 10)
        XCTAssertEqual(savedOverride, 0)
        let saved = try await observations.observations(carId: 1, stationKey: "geofence:home")
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.pricePerKWh == nil })
        XCTAssertTrue(saved.allSatisfy { $0.scope == .sessionOnly })
        let savedSettings = await settings.load()
        XCTAssertEqual(savedSettings.chargePricingRules, [existingRule])
    }

    func testFutureConfirmationDerivesUnitPriceAndCreatesScopedLearnedRule() async throws {
        let existingRule = ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.4)
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let settings = ResolverTestSettingsStore(AppSettings(chargePricingRules: [existingRule]))
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )
        let coordinates = GeocodeLocation(latitude: 31.230_456, longitude: 121.473_789)

        try await service.confirm(ChargePricingConfirmation(
            carId: 1,
            chargeId: 11,
            stationKey: "",
            scope: .futureAtStation,
            finalAmount: 12,
            billedEnergyKWh: 10,
            pricePerKWh: nil,
            serviceFeePerKWh: 0.2,
            fixedFee: 1,
            currencyCode: "CNY",
            coordinates: coordinates,
            chargerIdentity: .teslaSupercharger,
            startMinute: 60,
            endMinute: 120
        ))

        let stationKey = "31.2305,121.4738:teslaSupercharger"
        let saved = try await observations.observations(carId: 1, stationKey: stationKey)
        XCTAssertEqual(saved.first?.pricePerKWh ?? 0, 0.9, accuracy: 0.000_001)
        let savedOverride = try await overrides.costOverride(carId: 1, chargeId: 11)
        XCTAssertEqual(savedOverride, 12)

        let savedSettings = await settings.load()
        XCTAssertTrue(savedSettings.chargePricingRules.contains(existingRule))
        let learned = try XCTUnwrap(savedSettings.chargePricingRules.first { $0.origin == .stationLearned })
        XCTAssertTrue(learned.isEnabled)
        XCTAssertEqual(learned.chargeType, .teslaSupercharger)
        XCTAssertEqual(learned.latitude, coordinates.latitude)
        XCTAssertEqual(learned.longitude, coordinates.longitude)
        XCTAssertEqual(learned.radiusMeters, 150)
        XCTAssertEqual(learned.startMinuteOfDay, 60)
        XCTAssertEqual(learned.endMinuteOfDay, 120)
        XCTAssertEqual(learned.pricePerKWh, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(learned.serviceFeePerKWh, 0.2)
        XCTAssertEqual(learned.sessionFee, 1)
        XCTAssertEqual(learned.priority, 100)
        XCTAssertEqual(learned.currencyCode, "CNY")
        XCTAssertEqual(learned.stationKey, stationKey)
    }

    func testNewestStationConfirmationReplacesPriorLearnedRuleAndResolvesCorrection() async throws {
        let userRule = ChargePricingRule(id: "user", name: "User", pricePerKWh: 4, priority: 1)
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let settings = ResolverTestSettingsStore(AppSettings(chargePricingRules: [userRule]))
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        try await service.confirm(futureConfirmation(chargeId: 21, stationKey: "station-a", unitPrice: 1))
        try await service.confirm(futureConfirmation(chargeId: 22, stationKey: "station-a", unitPrice: 2))

        let savedSettings = await settings.load()
        XCTAssertTrue(savedSettings.chargePricingRules.contains(userRule))
        let learned = savedSettings.chargePricingRules.filter { $0.origin == .stationLearned }
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.pricePerKWh, 2)
        XCTAssertEqual(learned.first?.stationKey, "station-a")

        let result = ChargeCostResolver.resolve(makeInput(rules: learned))
        XCTAssertEqual(result?.unitPricePerKWh, 2)
        XCTAssertEqual(result?.amount, 20)
    }

    func testStationConfirmationReplacesMatchingAndLegacyCurrencyLearnedRules() async throws {
        let matchingCurrency = ChargePricingRule(
            id: "matching-currency",
            name: "Matching currency",
            chargeType: .ac,
            pricePerKWh: 1,
            origin: .stationLearned,
            currencyCode: "CNY",
            stationKey: "station-a"
        )
        let nilCurrency = ChargePricingRule(
            id: "nil-currency",
            name: "Nil currency",
            chargeType: .ac,
            pricePerKWh: 2,
            origin: .stationLearned,
            stationKey: "station-a"
        )
        var blankCurrency = ChargePricingRule(
            id: "blank-currency",
            name: "Blank currency",
            chargeType: .ac,
            pricePerKWh: 3,
            origin: .stationLearned,
            stationKey: "station-a"
        )
        blankCurrency.currencyCode = "  "
        let otherCurrency = ChargePricingRule(
            id: "other-currency",
            name: "Other currency",
            chargeType: .ac,
            pricePerKWh: 4,
            origin: .stationLearned,
            currencyCode: "USD",
            stationKey: "station-a"
        )
        let userRule = ChargePricingRule(id: "user", name: "User", pricePerKWh: 5)
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let settings = ResolverTestSettingsStore(AppSettings(chargePricingRules: [
            matchingCurrency,
            nilCurrency,
            blankCurrency,
            otherCurrency,
            userRule
        ]))
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        try await service.confirm(futureConfirmation(chargeId: 23, stationKey: "station-a", unitPrice: 6))

        let rules = await settings.load().chargePricingRules
        XCTAssertTrue(rules.contains(otherCurrency))
        XCTAssertTrue(rules.contains(userRule))
        XCTAssertFalse(rules.contains { [matchingCurrency, nilCurrency, blankCurrency].contains($0) })
        let learnedRules = rules.filter { $0.origin == .stationLearned }
        XCTAssertEqual(learnedRules.count, 2)
        XCTAssertEqual(learnedRules.first { $0.currencyCode == "CNY" }?.pricePerKWh, 6)
    }

    func testObservationFailureRemovesPartialObservationAndLeavesOtherStoresUnchanged() async {
        let observations = ResolverFailingObservationStore(failFirstSave: true)
        let overrides = ResolverFailingCostOverrideStore(initialValue: 4)
        let originalSettings = AppSettings(chargePricingRules: [
            ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.5)
        ])
        let settings = ResolverFailingSettingsStore(originalSettings)
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        await assertConfirmationThrows(
            service,
            value: futureConfirmation(chargeId: 30, stationKey: "station-failure", unitPrice: 1)
        )

        let savedOverride = try? await overrides.costOverride(carId: 1, chargeId: 30)
        let savedSettings = await settings.load()
        let savedObservations = try? await observations.observations(carId: 1, stationKey: "station-failure")
        XCTAssertEqual(savedOverride, 4)
        XCTAssertEqual(savedSettings, originalSettings)
        XCTAssertTrue(savedObservations?.isEmpty == true)
    }

    func testOverrideFailureRollsBackPartialOverrideAndObservation() async {
        let observations = ResolverFailingObservationStore()
        let overrides = ResolverFailingCostOverrideStore(initialValue: 4, failFirstSave: true)
        let originalSettings = AppSettings(chargePricingRules: [
            ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.5)
        ])
        let settings = ResolverFailingSettingsStore(originalSettings)
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        await assertConfirmationThrows(
            service,
            value: futureConfirmation(chargeId: 30, stationKey: "station-failure", unitPrice: 1)
        )

        let savedOverride = try? await overrides.costOverride(carId: 1, chargeId: 30)
        let savedSettings = await settings.load()
        let savedObservations = try? await observations.observations(carId: 1, stationKey: "station-failure")
        XCTAssertEqual(savedOverride, 4)
        XCTAssertEqual(savedSettings, originalSettings)
        XCTAssertTrue(savedObservations?.isEmpty == true)
    }

    func testSettingsFailureRestoresSettingsOverrideAndObservation() async {
        let observations = ResolverFailingObservationStore()
        let overrides = ResolverFailingCostOverrideStore(initialValue: 4)
        let originalSettings = AppSettings(chargePricingRules: [
            ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.5)
        ])
        let settings = ResolverFailingSettingsStore(originalSettings, failFirstSave: true)
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        await assertConfirmationThrows(
            service,
            value: futureConfirmation(chargeId: 30, stationKey: "station-failure", unitPrice: 1)
        )

        let savedOverride = try? await overrides.costOverride(carId: 1, chargeId: 30)
        let savedSettings = await settings.load()
        let savedObservations = try? await observations.observations(carId: 1, stationKey: "station-failure")
        XCTAssertEqual(savedOverride, 4)
        XCTAssertEqual(savedSettings, originalSettings)
        XCTAssertTrue(savedObservations?.isEmpty == true)
    }

    func testConcurrentConfirmationsDoNotLoseSettingsUpdates() async throws {
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let userRule = ChargePricingRule(id: "user", name: "User", pricePerKWh: 0.5)
        let settings = ResolverTestSettingsStore(AppSettings(chargePricingRules: [userRule]))
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        let firstValue = futureConfirmation(chargeId: 41, stationKey: "station-one", unitPrice: 1)
        let secondValue = futureConfirmation(chargeId: 42, stationKey: "station-two", unitPrice: 2)
        async let first: Void = service.confirm(firstValue)
        async let second: Void = service.confirm(secondValue)
        _ = try await (first, second)

        let concurrentSettings = await settings.load()
        let rules = concurrentSettings.chargePricingRules
        XCTAssertTrue(rules.contains(userRule))
        XCTAssertEqual(Set(rules.compactMap(\.stationKey)), ["station-one", "station-two"])
    }

    func testConfirmationRejectsOutOfRangeMinutesAndInvalidCurrencyBeforeWrites() async {
        let observations = ResolverTestObservationStore()
        let overrides = ResolverTestCostOverrideStore()
        let settings = ResolverTestSettingsStore(AppSettings())
        let service = ChargePricingObservationService(
            observationStore: observations,
            costOverrideStore: overrides,
            settingsStore: settings
        )

        var invalidMinute = futureConfirmation(chargeId: 50, stationKey: "invalid", unitPrice: 1)
        invalidMinute = ChargePricingConfirmation(
            carId: invalidMinute.carId,
            chargeId: invalidMinute.chargeId,
            stationKey: invalidMinute.stationKey,
            scope: invalidMinute.scope,
            finalAmount: invalidMinute.finalAmount,
            billedEnergyKWh: invalidMinute.billedEnergyKWh,
            pricePerKWh: invalidMinute.pricePerKWh,
            serviceFeePerKWh: invalidMinute.serviceFeePerKWh,
            fixedFee: invalidMinute.fixedFee,
            currencyCode: invalidMinute.currencyCode,
            coordinates: invalidMinute.coordinates,
            chargerIdentity: invalidMinute.chargerIdentity,
            startMinute: -1,
            endMinute: 1_440
        )
        do {
            try await service.confirm(invalidMinute)
            XCTFail("Expected invalid time window")
        } catch {
            XCTAssertEqual(error as? ChargePricingObservationServiceError, .invalidTimeWindow)
        }

        let invalidCurrency = ChargePricingConfirmation(
            carId: 1,
            chargeId: 51,
            stationKey: "invalid",
            scope: .sessionOnly,
            finalAmount: 1,
            billedEnergyKWh: 1,
            pricePerKWh: 1,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: "US",
            coordinates: nil,
            chargerIdentity: .ac,
            startMinute: nil,
            endMinute: nil
        )
        do {
            try await service.confirm(invalidCurrency)
            XCTFail("Expected invalid currency")
        } catch {
            XCTAssertEqual(error as? ChargePricingObservationServiceError, .invalidCurrency)
        }

        let savedOverride = try? await overrides.costOverride(carId: 1, chargeId: 50)
        let savedObservations = try? await observations.observations(carId: 1, stationKey: "invalid")
        XCTAssertNil(savedOverride)
        XCTAssertTrue(savedObservations?.isEmpty == true)
    }

    private func makeInput(
        manualCost: Double? = nil,
        apiCost: Double? = nil,
        currencyCode: String = "CNY",
        isAC: Bool = true,
        geofenceKind: GeofenceKind? = nil,
        pricingInput: ChargePricingInput? = nil,
        rules: [ChargePricingRule] = [],
        regionalRule: ChargePricingRule? = nil
    ) -> ChargeCostResolutionInput {
        ChargeCostResolutionInput(
            manualCost: manualCost,
            apiCost: apiCost,
            currencyCode: currencyCode,
            isAC: isAC,
            geofenceKind: geofenceKind,
            pricingInput: pricingInput ?? self.pricingInput(),
            rules: rules,
            regionalRule: regionalRule
        )
    }

    private func pricingInput(isDc: Bool = false) -> ChargePricingInput {
        ChargePricingInput(
            startDate: "2026-07-01T09:00:00+08:00",
            address: "Home",
            latitude: nil,
            longitude: nil,
            energyAddedKWh: 10,
            isDc: isDc
        )
    }

    private func stationRule(
        id: String = "station",
        price: Double,
        priority: Int = 100
    ) -> ChargePricingRule {
        ChargePricingRule(
            id: id,
            name: "Station",
            pricePerKWh: price,
            priority: priority,
            origin: .stationLearned
        )
    }

    private func regionalRule(price: Double) -> ChargePricingRule {
        ChargePricingRule(
            id: "regional",
            name: "Regional",
            chargeType: .ac,
            effectiveFromDate: "2026-01-01",
            effectiveToDate: "2026-12-31",
            pricePerKWh: price,
            origin: .regionalOfficial,
            regionCode: "CN-43",
            sourceURL: "https://example.com/tariff",
            verifiedAt: "2026-07-18",
            currencyCode: "CNY"
        )
    }

    private func futureConfirmation(
        chargeId: Int,
        stationKey: String,
        unitPrice: Double
    ) -> ChargePricingConfirmation {
        ChargePricingConfirmation(
            carId: 1,
            chargeId: chargeId,
            stationKey: stationKey,
            scope: .futureAtStation,
            finalAmount: unitPrice * 10,
            billedEnergyKWh: 10,
            pricePerKWh: unitPrice,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: "CNY",
            coordinates: GeocodeLocation(latitude: 31.2304, longitude: 121.4737),
            chargerIdentity: .ac,
            startMinute: nil,
            endMinute: nil
        )
    }

    private func assertConfirmationThrows(
        _ service: ChargePricingObservationService,
        value: ChargePricingConfirmation
    ) async {
        do {
            try await service.confirm(value)
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertTrue(error is ResolverInjectedFailure)
        }
    }
}

private actor ResolverTestObservationStore: ChargePricingObservationStoring {
    private var values: [ChargePricingObservation] = []

    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] {
        values.filter { $0.carId == carId && $0.stationKey == stationKey }
    }

    func save(_ value: ChargePricingObservation) async throws {
        values.append(value)
    }

    func remove(id: String) async throws {
        values.removeAll { $0.id == id }
    }

    func removeAll() async throws {
        values.removeAll()
    }
}

private enum ResolverInjectedFailure: Error {
    case injected
}

private actor ResolverFailingObservationStore: ChargePricingObservationStoring {
    private var values: [ChargePricingObservation] = []
    private var failFirstSave: Bool

    init(failFirstSave: Bool = false) {
        self.failFirstSave = failFirstSave
    }

    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] {
        values.filter { $0.carId == carId && $0.stationKey == stationKey }
    }

    func save(_ value: ChargePricingObservation) async throws {
        values.append(value)
        if failFirstSave {
            failFirstSave = false
            throw ResolverInjectedFailure.injected
        }
    }

    func remove(id: String) async throws {
        values.removeAll { $0.id == id }
    }

    func removeAll() async throws {
        values.removeAll()
    }
}

private actor ResolverFailingCostOverrideStore: ChargeCostOverriding {
    private var value: Double?
    private var failFirstSave: Bool

    init(initialValue: Double?, failFirstSave: Bool = false) {
        value = initialValue
        self.failFirstSave = failFirstSave
    }

    func costOverrides(carId _: Int) async throws -> [Int: Double] {
        value.map { [30: $0] } ?? [:]
    }

    func costOverride(carId _: Int, chargeId _: Int) async throws -> Double? {
        value
    }

    func saveCostOverride(carId _: Int, chargeId _: Int, cost: Double?) async throws {
        value = cost
        if failFirstSave {
            failFirstSave = false
            throw ResolverInjectedFailure.injected
        }
    }
}

private actor ResolverFailingSettingsStore: SettingsStoring {
    private var settings: AppSettings
    private var failFirstSave: Bool

    init(_ settings: AppSettings, failFirstSave: Bool = false) {
        self.settings = settings
        self.failFirstSave = failFirstSave
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        self.settings = settings
    }

    func saveThrowing(_ settings: AppSettings) async throws {
        self.settings = settings
        if failFirstSave {
            failFirstSave = false
            throw ResolverInjectedFailure.injected
        }
    }
}

private actor ResolverTestCostOverrideStore: ChargeCostOverriding {
    private var values: [Int: [Int: Double]] = [:]

    func costOverrides(carId: Int) async throws -> [Int: Double] {
        values[carId] ?? [:]
    }

    func costOverride(carId: Int, chargeId: Int) async throws -> Double? {
        values[carId]?[chargeId]
    }

    func saveCostOverride(carId: Int, chargeId: Int, cost: Double?) async throws {
        values[carId, default: [:]][chargeId] = cost
    }
}

private actor ResolverTestSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(_ settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        self.settings = settings
    }
}
