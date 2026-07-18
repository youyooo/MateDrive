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
            origin: .regionalOfficial
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
            origin: .regionalOfficial
        )
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

    func removeAll() async throws {
        values.removeAll()
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
