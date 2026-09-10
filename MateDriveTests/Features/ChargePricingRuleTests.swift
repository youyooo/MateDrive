import XCTest
@testable import MateDriveApp

final class ChargePricingRuleTests: XCTestCase {
    func testEstimateAddsServiceFeeAndKeepsParkingAsReference() {
        let rule = ChargePricingRule(
            id: "fees",
            name: "Fees",
            pricePerKWh: 0.5,
            sessionFee: 1,
            serviceFeePerKWh: 0.2,
            parkingFeeRuleID: "parking-1"
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T09:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.energyCost, 5)
        XCTAssertEqual(estimate?.serviceFee, 2)
        XCTAssertEqual(estimate?.sessionFee, 1)
        XCTAssertEqual(estimate?.cost, 8)
        XCTAssertEqual(estimate?.rule.parkingFeeRuleID, "parking-1")
    }

    func testTariffTemplateExcludesLocationDateAndPriorityFromPersistence() throws {
        let point = SyntheticCoordinates.point()
        let rule = ChargePricingRule(
            id: "source",
            name: "Source Rule",
            chargeType: .otherDC,
            addressKeyword: "Sample Network",
            latitude: point.latitude,
            longitude: point.longitude,
            radiusMeters: 750,
            effectiveFromDate: "2026-01-01",
            effectiveToDate: "2026-12-31",
            pricePerKWh: 1.8,
            timeSegments: [
                ChargePricingTimeSegment(id: "source-segment", startMinuteOfDay: 0, endMinuteOfDay: 479, pricePerKWh: 1.2),
                ChargePricingTimeSegment(id: "source-segment-2", startMinuteOfDay: 480, endMinuteOfDay: 1_439, pricePerKWh: 1.8)
            ],
            sessionFee: 2,
            priority: 9
        )

        let template = ChargeTariffTemplate(id: "template", name: "Public DC", rule: rule)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any]
        )

        XCTAssertNil(object["addressKeyword"])
        XCTAssertNil(object["latitude"])
        XCTAssertNil(object["longitude"])
        XCTAssertNil(object["radiusMeters"])
        XCTAssertNil(object["effectiveFromDate"])
        XCTAssertNil(object["effectiveToDate"])
        XCTAssertNil(object["priority"])
        XCTAssertEqual(template.chargeType, .otherDC)
        XCTAssertEqual(template.timeSegments.count, 2)
        XCTAssertTrue(template.validationIssues.isEmpty)
    }

    func testTariffTemplateCreatesIndependentLocationlessRule() {
        let template = ChargeTariffTemplate(
            id: "template",
            name: "Night Rate",
            chargeType: .ac,
            startMinuteOfDay: 22 * 60,
            endMinuteOfDay: 7 * 60,
            pricePerKWh: 0.8,
            timeSegments: [
                ChargePricingTimeSegment(id: "template-segment", startMinuteOfDay: 22 * 60, endMinuteOfDay: 7 * 60, pricePerKWh: 0.4)
            ],
            sessionFee: 1
        )

        let rule = template.makeRule(id: "new-rule")

        XCTAssertEqual(rule.id, "new-rule")
        XCTAssertEqual(rule.name, "Night Rate")
        XCTAssertEqual(rule.chargeType, .ac)
        XCTAssertNil(rule.addressKeyword)
        XCTAssertNil(rule.latitude)
        XCTAssertNil(rule.longitude)
        XCTAssertNil(rule.radiusMeters)
        XCTAssertNil(rule.effectiveFromDate)
        XCTAssertNil(rule.effectiveToDate)
        XCTAssertEqual(rule.priority, 0)
        XCTAssertNotEqual(rule.timeSegments.first?.id, template.timeSegments.first?.id)
        XCTAssertTrue(ChargePricingRuleValidator.issues(for: rule).isEmpty)
    }

    func testApplyingTariffTemplatePreservesRuleScopeAndReplacesOnlyPricing() {
        let point = SyntheticCoordinates.point()
        let rule = ChargePricingRule(
            id: "existing",
            name: "Existing Place",
            chargeType: .ac,
            addressKeyword: "Sample Place",
            latitude: point.latitude,
            longitude: point.longitude,
            radiusMeters: 500,
            effectiveFromDate: "2026-01-01",
            effectiveToDate: "2026-06-30",
            pricePerKWh: 0.5,
            priority: 7
        )
        let template = ChargeTariffTemplate(
            name: "Fast Charging",
            chargeType: .teslaSupercharger,
            pricePerKWh: 2.2,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 1_439, pricePerKWh: 2.2)
            ],
            sessionFee: 3
        )

        let updated = template.applying(to: rule)

        XCTAssertEqual(updated.id, rule.id)
        XCTAssertEqual(updated.name, rule.name)
        XCTAssertEqual(updated.addressKeyword, rule.addressKeyword)
        XCTAssertEqual(updated.latitude, rule.latitude)
        XCTAssertEqual(updated.longitude, rule.longitude)
        XCTAssertEqual(updated.radiusMeters, rule.radiusMeters)
        XCTAssertEqual(updated.effectiveFromDate, rule.effectiveFromDate)
        XCTAssertEqual(updated.effectiveToDate, rule.effectiveToDate)
        XCTAssertEqual(updated.priority, rule.priority)
        XCTAssertEqual(updated.chargeType, .teslaSupercharger)
        XCTAssertEqual(updated.pricePerKWh, 2.2)
        XCTAssertEqual(updated.sessionFee, 3)
        XCTAssertEqual(updated.timeSegments.count, 1)
    }

    func testRuleValidatorRejectsIncompleteAndInvalidLocation() {
        let incomplete = ChargePricingRule(name: "Incomplete", latitude: SyntheticCoordinates.point().latitude, pricePerKWh: 1)
        let invalid = ChargePricingRule(name: "Invalid", latitude: SyntheticCoordinates.invalidLatitude, longitude: SyntheticCoordinates.point().longitude, radiusMeters: -1, pricePerKWh: 1)

        XCTAssertTrue(ChargePricingRuleValidator.issues(for: incomplete).contains(.incompleteLocation))
        XCTAssertTrue(ChargePricingRuleValidator.issues(for: invalid).contains(.invalidLocation))
    }

    func testRuleValidatorRejectsInvalidPricesAndIncompleteTimeWindow() {
        let rule = ChargePricingRule(
            name: "Invalid",
            startMinuteOfDay: 60,
            pricePerKWh: -.infinity,
            sessionFee: -1
        )

        let issues = ChargePricingRuleValidator.issues(for: rule)
        XCTAssertTrue(issues.contains(.invalidPrice))
        XCTAssertTrue(issues.contains(.invalidSessionFee))
        XCTAssertTrue(issues.contains(.incompleteTimeWindow))
    }

    func testRuleValidatorRejectsOutOfRangeRuleAndSegmentMinutes() {
        let rule = ChargePricingRule(
            name: "Invalid minutes",
            startMinuteOfDay: -1,
            endMinuteOfDay: 1_440,
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: -1,
                    endMinuteOfDay: 1_440,
                    pricePerKWh: 1
                )
            ]
        )

        let issues = ChargePricingRuleValidator.issues(for: rule)
        XCTAssertTrue(issues.contains(.invalidTimeWindow))
        XCTAssertTrue(issues.contains(.invalidTimeSegment))
    }

    func testRuleCurrencyNormalizesAndRejectsMalformedExplicitCode() {
        let normalized = ChargePricingRule(name: "USD", pricePerKWh: 1, currencyCode: " usd ")
        let malformed = ChargePricingRule(name: "Bad", pricePerKWh: 1, currencyCode: "US1")

        XCTAssertEqual(normalized.currencyCode, "USD")
        XCTAssertFalse(ChargePricingRuleValidator.issues(for: normalized).contains(.invalidCurrency))
        XCTAssertTrue(ChargePricingRuleValidator.issues(for: malformed).contains(.invalidCurrency))
    }

    func testEditorMetadataPreservationKeepsParkingCurrencyStationAndProvenance() {
        let original = ChargePricingRule(
            id: "learned",
            name: "Original",
            effectiveFromDate: "2026-01-01",
            effectiveToDate: "2026-12-31",
            pricePerKWh: 1,
            origin: .stationLearned,
            regionCode: "CN-43",
            sourceURL: "https://example.com/source",
            verifiedAt: "2026-07-18",
            serviceFeePerKWh: 0.2,
            parkingFeeRuleID: "parking-1",
            applicableWeekdays: [2, 3],
            applicableMonths: [7, 8],
            currencyCode: "CNY",
            stationKey: "station-a"
        )
        let editedDraft = ChargePricingRule(
            id: original.id,
            name: "Edited",
            pricePerKWh: 2
        )

        let edited = editedDraft.preservingEditorMetadata(from: original)

        XCTAssertEqual(edited.name, "Edited")
        XCTAssertEqual(edited.pricePerKWh, 2)
        XCTAssertEqual(edited.origin, original.origin)
        XCTAssertEqual(edited.regionCode, original.regionCode)
        XCTAssertEqual(edited.sourceURL, original.sourceURL)
        XCTAssertEqual(edited.verifiedAt, original.verifiedAt)
        XCTAssertEqual(edited.serviceFeePerKWh, original.serviceFeePerKWh)
        XCTAssertEqual(edited.parkingFeeRuleID, original.parkingFeeRuleID)
        XCTAssertEqual(edited.applicableWeekdays, original.applicableWeekdays)
        XCTAssertEqual(edited.applicableMonths, original.applicableMonths)
        XCTAssertEqual(edited.currencyCode, original.currencyCode)
        XCTAssertEqual(edited.stationKey, original.stationKey)
    }

    func testRuleValidatorDetectsOverlapIncludingAcrossMidnight() {
        let rule = ChargePricingRule(
            name: "Overlap",
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 22 * 60, endMinuteOfDay: 2 * 60, pricePerKWh: 0.5),
                ChargePricingTimeSegment(startMinuteOfDay: 60, endMinuteOfDay: 3 * 60, pricePerKWh: 0.8)
            ]
        )

        XCTAssertTrue(ChargePricingRuleValidator.issues(for: rule).contains(.overlappingTimeSegments))
    }

    func testRuleValidatorAcceptsAdjacentCompleteSegments() {
        let location = SyntheticCoordinates.point()
        let rule = ChargePricingRule(
            name: "Valid",
            latitude: location.latitude,
            longitude: location.longitude,
            radiusMeters: 300,
            startMinuteOfDay: 0,
            endMinuteOfDay: 1_439,
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 6 * 60 + 59, pricePerKWh: 0.5),
                ChargePricingTimeSegment(startMinuteOfDay: 7 * 60, endMinuteOfDay: 1_439, pricePerKWh: 1.2)
            ]
        )

        XCTAssertTrue(ChargePricingRuleValidator.issues(for: rule).isEmpty)
    }

    func testEngineIgnoresInvalidPersistedRuleInsteadOfApplyingItGlobally() {
        let location = SyntheticCoordinates.point()
        let invalidLegacyRule = ChargePricingRule(
            id: "legacy",
            name: "Legacy Location",
            latitude: location.latitude,
            pricePerKWh: 0.1,
            priority: 100
        )
        let validRule = ChargePricingRule(id: "valid", name: "Valid", pricePerKWh: 1, priority: 0)

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:00:00+08:00",
                address: "Unrelated Station",
                latitude: location.latitude,
                longitude: location.longitude,
                energyAddedKWh: 10,
                isDc: false
            ),
            rules: [invalidLegacyRule, validRule]
        )

        XCTAssertEqual(estimate?.rule.id, "valid")
        XCTAssertEqual(estimate?.cost, 10)
    }

    func testCostSourceDisplayTextLocalizesDynamicValues() {
        XCTAssertEqual(ChargeCostSource.manual.displayText(language: .chinese), "本地手动价格")
        XCTAssertEqual(ChargeCostSource.pricingRule.displayText(language: .chinese), "价格规则")
        XCTAssertEqual(ChargeCostSource.api.displayText(language: .chinese), "TeslaMate API 价格")
        XCTAssertEqual(ChargeCostSource.none.displayText(language: .chinese), "未记录费用")
        XCTAssertEqual(ChargeCostSource.manual.displayText(language: .english), "Local manual price")
    }

    func testChargeTypeDisplayTextLocalizesVisibleLabels() {
        XCTAssertEqual(ChargePricingChargeType.any.displayText(language: .chinese), "任意")
        XCTAssertEqual(ChargePricingChargeType.ac.displayText(language: .chinese), "交流")
        XCTAssertEqual(ChargePricingChargeType.dc.displayText(language: .chinese), "直流")
        XCTAssertEqual(ChargePricingChargeType.ac.displayText(language: .english), "AC")
        XCTAssertEqual(ChargePricingChargeType.teslaSupercharger.displayText(language: .chinese), "特斯拉超充")
        XCTAssertEqual(ChargePricingChargeType.otherDC.displayText(language: .chinese), "其他直流桩")
        XCTAssertEqual(ChargeTypeFilter.ac.title(language: .chinese), "交流")
        XCTAssertEqual(ChargeTypeFilter.dc.title(language: .chinese), "直流")
    }

    func testSpecificDcRulesRequireVerifiedChargerIdentity() {
        let tesla = ChargePricingRule(id: "tesla", name: "Tesla", chargeType: .teslaSupercharger, pricePerKWh: 2)
        let thirdParty = ChargePricingRule(id: "third", name: "Third", chargeType: .otherDC, pricePerKWh: 1)

        let unknown = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: nil, address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: true),
            rules: [tesla, thirdParty]
        )
        let verified = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: nil, address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: true, chargerIdentity: .teslaSupercharger),
            rules: [tesla, thirdParty]
        )

        XCTAssertNil(unknown)
        XCTAssertEqual(verified?.rule.id, "tesla")
    }

    func testChargerIdentityUsesTeslaBrandFromAnyRecordedSample() {
        let detail = ChargeDetail(
            chargeId: 1,
            chargePoints: [
                ChargePoint(chargerDetails: ChargerDetails(chargerPhases: 0, fastChargerPresent: true, fastChargerBrand: "Other")),
                ChargePoint(chargerDetails: ChargerDetails(chargerPhases: 0, fastChargerPresent: true, fastChargerBrand: "Tesla"))
            ]
        )

        XCTAssertEqual(ChargingSessionAnalyzer.chargerIdentity(detail), .teslaSupercharger)
    }

    func testRuleMatchesAddressTimeTypeAndCalculatesSessionCost() {
        let rule = ChargePricingRule(
            id: "supercharger-peak",
            name: "Supercharger Peak",
            chargeType: .dc,
            addressKeyword: "Supercharger",
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 22 * 60,
            pricePerKWh: 1.8,
            sessionFee: 2,
            priority: 10
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:00:00Z",
                address: "Tesla Supercharger",
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                isDc: true
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.rule.id, "supercharger-peak")
        XCTAssertEqual(estimate?.cost, 38)
    }

    func testRuleMatchesOvernightWindowAndLocationRadius() {
        let ruleLocation = SyntheticCoordinates.point()
        let nearbyInput = SyntheticCoordinates.point(latitudeOffset: 0.0005, longitudeOffset: 0.0005)
        let rule = ChargePricingRule(
            id: "home-valley",
            name: "Home Valley",
            chargeType: .ac,
            latitude: ruleLocation.latitude,
            longitude: ruleLocation.longitude,
            radiusMeters: 300,
            startMinuteOfDay: 22 * 60,
            endMinuteOfDay: 7 * 60,
            pricePerKWh: 0.45
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T23:30:00+08:00",
                address: nil,
                latitude: nearbyInput.latitude,
                longitude: nearbyInput.longitude,
                energyAddedKWh: 40,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.rule.id, "home-valley")
        XCTAssertEqual(estimate?.cost, 18)
    }

    func testHigherPriorityRuleWinsWhenMultipleRulesMatch() {
        let defaultRule = ChargePricingRule(id: "default", name: "Default", pricePerKWh: 1, priority: 0)
        let preferredRule = ChargePricingRule(id: "preferred", name: "Preferred", pricePerKWh: 2, priority: 5)

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T12:00:00Z",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                isDc: false
            ),
            rules: [defaultRule, preferredRule]
        )

        XCTAssertEqual(estimate?.rule.id, "preferred")
        XCTAssertEqual(estimate?.cost, 20)
    }

    func testEffectiveDateSelectsHistoricalPriceBeforePriority() {
        let oldPrice = ChargePricingRule(
            id: "home-2025",
            name: "Home 2025",
            effectiveToDate: "2025-12-31",
            pricePerKWh: 0.5,
            priority: 10
        )
        let newPrice = ChargePricingRule(
            id: "home-2026",
            name: "Home 2026",
            effectiveFromDate: "2026-01-01",
            pricePerKWh: 0.8,
            priority: 20
        )

        let oldEstimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: "2025-12-31T23:30:00+08:00", address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: false),
            rules: [newPrice, oldPrice]
        )
        let newEstimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: "2026-01-01T00:30:00+08:00", address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: false),
            rules: [oldPrice, newPrice]
        )

        XCTAssertEqual(oldEstimate?.rule.id, "home-2025")
        XCTAssertEqual(oldEstimate?.cost, 5)
        XCTAssertEqual(newEstimate?.rule.id, "home-2026")
        XCTAssertEqual(newEstimate?.cost, 8)
    }

    func testEffectiveDateUsesTimestampLocalCalendarDate() {
        let rule = ChargePricingRule(
            id: "new-year",
            name: "New Year",
            effectiveFromDate: "2026-01-01",
            pricePerKWh: 1
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: "2026-01-01T00:15:00+08:00", address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: false),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.rule.id, "new-year")
    }

    func testDateBoundRuleDoesNotMatchMissingOrInvalidChargeTimestamp() {
        let rule = ChargePricingRule(name: "Dated", effectiveFromDate: "2026-01-01", pricePerKWh: 1)

        let missing = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: nil, address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: false),
            rules: [rule]
        )
        let invalid = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(startDate: "invalid", address: nil, latitude: nil, longitude: nil, energyAddedKWh: 10, isDc: false),
            rules: [rule]
        )

        XCTAssertNil(missing)
        XCTAssertNil(invalid)
    }

    func testRuleValidatorRejectsInvalidEffectiveDateRange() {
        let reversed = ChargePricingRule(
            name: "Reversed",
            effectiveFromDate: "2026-02-01",
            effectiveToDate: "2026-01-31",
            pricePerKWh: 1
        )
        let invalid = ChargePricingRule(name: "Invalid", effectiveFromDate: "2026-02-30", pricePerKWh: 1)

        XCTAssertTrue(ChargePricingRuleValidator.issues(for: reversed).contains(.invalidEffectiveDateRange))
        XCTAssertTrue(ChargePricingRuleValidator.issues(for: invalid).contains(.invalidEffectiveDateRange))
    }

    func testTimeSegmentPriceOverridesDefaultPriceForMatchingStartTime() {
        let rule = ChargePricingRule(
            id: "third-party-station",
            name: "Third Party Station",
            pricePerKWh: 1.2,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 7 * 60, pricePerKWh: 0.7),
                ChargePricingTimeSegment(startMinuteOfDay: 7 * 60 + 1, endMinuteOfDay: 22 * 60, pricePerKWh: 1.6)
            ],
            sessionFee: 1
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:30:00Z",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                isDc: true
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost, 33)
    }

    func testTimeSegmentFallsBackToDefaultPriceWhenNoSegmentMatches() {
        let rule = ChargePricingRule(
            id: "fallback",
            name: "Fallback",
            startMinuteOfDay: 0,
            endMinuteOfDay: 23 * 60 + 59,
            pricePerKWh: 1.2,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 7 * 60, pricePerKWh: 0.7)
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:30:00Z",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost, 12)
    }

    func testTimeSegmentUsesTimestampTimeZoneInsteadOfDeviceTimeZone() {
        let previousTimeZone = TimeZone.ReferenceType.default
        TimeZone.ReferenceType.default = TimeZone(secondsFromGMT: 0)!
        defer { TimeZone.ReferenceType.default = previousTimeZone }

        let rule = ChargePricingRule(
            id: "timezone",
            name: "Time Zone",
            pricePerKWh: 9,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 23 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 2)
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T23:30:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                isDc: true
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost, 20)
    }

    func testEnergySamplesSplitCostAcrossTimeSegments() {
        let rule = ChargePricingRule(
            id: "split",
            name: "Split",
            pricePerKWh: 9,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T18:30:00+08:00",
                endDate: "2026-07-01T19:30:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T18:30:00+08:00", cumulativeEnergyAddedKWh: 0),
                    ChargePricingEnergySample(date: "2026-07-01T19:30:00+08:00", cumulativeEnergyAddedKWh: 10)
                ],
                isDc: true
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(estimate?.components.count, 2)
        XCTAssertEqual(estimate?.components.reduce(0) { $0 + $1.energyKWh } ?? 0, 10, accuracy: 0.001)
    }

    func testPricingRejectsNegativeAndNonFiniteTotalEnergyButAllowsZeroSessionFee() {
        let rule = ChargePricingRule(
            name: "Fixed fee",
            pricePerKWh: 2,
            sessionFee: 3,
            serviceFeePerKWh: 4
        )

        let invalidEnergies: [Double] = [-1, .nan, .infinity, -.infinity]
        for energy in invalidEnergies {
            let estimate = ChargePricingRuleEngine.estimateCost(
                for: ChargePricingInput(
                    startDate: "2026-07-01T10:00:00+08:00",
                    address: nil,
                    latitude: nil,
                    longitude: nil,
                    energyAddedKWh: energy,
                    isDc: false
                ),
                rules: [rule]
            )
            XCTAssertNil(estimate, "energy=\(energy)")
        }

        let zero = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 0,
                isDc: false
            ),
            rules: [rule]
        )
        XCTAssertEqual(zero?.cost, 3)
        XCTAssertEqual(zero?.serviceFee, 0)
        XCTAssertEqual(zero?.components, [])
    }

    func testPricingReturnsNilWhenFiniteArithmeticOverflows() {
        let energy = Double.greatestFiniteMagnitude
        let input = ChargePricingInput(
            startDate: "2026-07-01T10:00:00+08:00",
            address: nil,
            latitude: nil,
            longitude: nil,
            energyAddedKWh: energy,
            isDc: false
        )
        let overflowingComponent = ChargePricingRule(
            name: "Component overflow",
            pricePerKWh: 2
        )
        let overflowingServiceFee = ChargePricingRule(
            name: "Service fee overflow",
            pricePerKWh: 0,
            serviceFeePerKWh: 2
        )
        let overflowingSubtotal = ChargePricingRule(
            name: "Subtotal overflow",
            pricePerKWh: 1,
            serviceFeePerKWh: 1
        )
        let overflowingFinalCost = ChargePricingRule(
            name: "Final cost overflow",
            pricePerKWh: 1,
            sessionFee: .greatestFiniteMagnitude
        )

        for rule in [
            overflowingComponent,
            overflowingServiceFee,
            overflowingSubtotal,
            overflowingFinalCost
        ] {
            XCTAssertNil(ChargePricingRuleEngine.estimateCost(for: input, rules: [rule]), rule.name)
        }
    }

    func testPricingRejectsMergedComponentEnergyOverflow() {
        let rule = ChargePricingRule(
            name: "Zero-price segmented overflow",
            pricePerKWh: 0,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 1_439,
                    pricePerKWh: 0
                )
            ]
        )
        let input = ChargePricingInput(
            startDate: "2026-07-01T10:00:00+08:00",
            endDate: "2026-07-01T10:11:00+08:00",
            address: nil,
            latitude: nil,
            longitude: nil,
            energyAddedKWh: .greatestFiniteMagnitude,
            isDc: false
        )

        XCTAssertNil(ChargePricingRuleEngine.estimateCost(for: input, rules: [rule]))
    }

    func testEnergySamplesStayWithinSessionAndNeverExceedBilledEnergy() {
        let rule = ChargePricingRule(
            name: "Bounded samples",
            pricePerKWh: 50,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 10 * 60, endMinuteOfDay: 10 * 60 + 29, pricePerKWh: 1),
                ChargePricingTimeSegment(startMinuteOfDay: 10 * 60 + 30, endMinuteOfDay: 11 * 60, pricePerKWh: 100)
            ],
            serviceFeePerKWh: 2
        )
        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T10:00:00+08:00",
                endDate: "2026-07-01T11:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 5,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T09:30:00+08:00", cumulativeEnergyAddedKWh: 100),
                    ChargePricingEnergySample(date: "2026-07-01T10:00:00+08:00", cumulativeEnergyAddedKWh: 0),
                    ChargePricingEnergySample(date: "2026-07-01T10:10:00+08:00", cumulativeEnergyAddedKWh: 3),
                    ChargePricingEnergySample(date: "2026-07-01T10:20:00+08:00", cumulativeEnergyAddedKWh: 2),
                    ChargePricingEnergySample(date: "2026-07-01T10:30:00+08:00", cumulativeEnergyAddedKWh: 10),
                    ChargePricingEnergySample(date: "2026-07-01T10:40:00+08:00", cumulativeEnergyAddedKWh: .infinity),
                    ChargePricingEnergySample(date: "2026-07-01T11:30:00+08:00", cumulativeEnergyAddedKWh: 20)
                ],
                isDc: false
            ),
            rules: [rule]
        )

        let allocatedEnergy = estimate?.components.reduce(0) { $0 + $1.energyKWh } ?? 0
        XCTAssertEqual(allocatedEnergy, 5, accuracy: 0.000_001)
        XCTAssertEqual(estimate?.serviceFee, 10)
        XCTAssertEqual(estimate?.cost ?? 0, 15, accuracy: 0.000_001)
    }

    func testTimeSegmentsSplitCostByDurationWhenEnergySamplesAreMissing() {
        let rule = ChargePricingRule(
            id: "duration-fallback",
            name: "Duration Fallback",
            pricePerKWh: 9,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T18:30:00+08:00",
                endDate: "2026-07-01T19:30:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                isDc: true
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost ?? 0, 20, accuracy: 0.001)
    }

    func testTimeSegmentsSplitCostAcrossMidnightWhenEnergySamplesAreMissing() {
        let rule = ChargePricingRule(
            id: "overnight-duration-fallback",
            name: "Overnight Duration Fallback",
            pricePerKWh: 5,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 22 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 2),
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 7 * 60, pricePerKWh: 0.5)
            ],
            sessionFee: 1
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T23:00:00+08:00",
                endDate: "2026-07-02T01:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost ?? 0, 26, accuracy: 0.001)
    }

    func testTimeSegmentEstimateRejectsUnboundedDurationInterpolation() {
        let rule = ChargePricingRule(
            id: "unbounded-duration",
            name: "Unbounded Duration",
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 1_439,
                    pricePerKWh: 1
                )
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T00:00:00+08:00",
                endDate: "2026-07-09T00:00:01+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertNil(estimate)
    }

    func testTimeSegmentEstimateRejectsPositiveEnergyAcrossUnboundedSampleGap() {
        let rule = ChargePricingRule(
            id: "unbounded-sample-gap",
            name: "Unbounded Sample Gap",
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 1_439,
                    pricePerKWh: 1
                )
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T00:00:00+08:00",
                endDate: "2026-07-09T00:00:01+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                energySamples: [
                    ChargePricingEnergySample(
                        date: "2026-07-09T00:00:01+08:00",
                        cumulativeEnergyAddedKWh: 20
                    )
                ],
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertNil(estimate)
    }

    func testTimeSegmentEstimateRejectsEndBeforeStart() {
        let rule = ChargePricingRule(
            id: "reversed-session",
            name: "Reversed Session",
            pricePerKWh: 1,
            timeSegments: [
                ChargePricingTimeSegment(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 1_439,
                    pricePerKWh: 1
                )
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-02T01:00:00+08:00",
                endDate: "2026-07-02T00:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 20,
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertNil(estimate)
    }

    func testEnergySamplesAllocateResidualEnergyUntilChargeEnd() {
        let rule = ChargePricingRule(
            id: "residual",
            name: "Residual",
            pricePerKWh: 2,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 2)
            ],
            sessionFee: 1
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T18:00:00+08:00",
                endDate: "2026-07-01T19:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T18:30:00+08:00", cumulativeEnergyAddedKWh: 4)
                ],
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost ?? 0, 21, accuracy: 0.001)
    }

    func testEnergySamplesAllocateResidualEnergyWithoutChargeEndDate() {
        let rule = ChargePricingRule(
            id: "residual-no-end",
            name: "Residual No End",
            pricePerKWh: 9,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
            ]
        )

        let estimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: "2026-07-01T18:00:00+08:00",
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 10,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T19:00:00+08:00", cumulativeEnergyAddedKWh: 4)
                ],
                isDc: false
            ),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.cost ?? 0, 22, accuracy: 0.001)
    }

    func testLegacyRuleJSONDecodesMissingTimeSegmentsAsEmptyArray() throws {
        let json = """
        {
          "id": "legacy",
          "name": "Legacy",
          "isEnabled": true,
          "chargeType": "any",
          "pricePerKWh": 1.1,
          "sessionFee": 0,
          "priority": 0
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(ChargePricingRule.self, from: json)

        XCTAssertEqual(rule.id, "legacy")
        XCTAssertEqual(rule.pricePerKWh, 1.1)
        XCTAssertEqual(rule.timeSegments, [])
        XCTAssertNil(rule.effectiveFromDate)
        XCTAssertNil(rule.effectiveToDate)
    }

    func testManualCostExplanationStatesConfirmationAndPriority() throws {
        let explanation = try XCTUnwrap(ChargeCostExplanationBuilder.build(
            source: .manual,
            ruleName: nil,
            matchFactors: [],
            components: [],
            sessionFee: 0,
            language: .chinese
        ))

        XCTAssertEqual(explanation.status, "已确认")
        XCTAssertTrue(explanation.summary.contains("优先"))
        XCTAssertTrue(explanation.allowsCorrection)
        XCTAssertTrue(explanation.evidence.isEmpty)
    }

    func testPricingRuleExplanationUsesActualRuleSegmentsAndEnergy() throws {
        let components = [
            ChargePricingCostComponent(
                startMinuteOfDay: 0,
                endMinuteOfDay: 359,
                energyKWh: 8.25,
                pricePerKWh: 0.5,
                cost: 4.125
            ),
            ChargePricingCostComponent(
                startMinuteOfDay: 360,
                endMinuteOfDay: 719,
                energyKWh: 1.75,
                pricePerKWh: 0.8,
                cost: 1.4
            )
        ]

        let explanation = try XCTUnwrap(ChargeCostExplanationBuilder.build(
            source: .pricingRule,
            ruleName: "Home off-peak",
            matchFactors: [.savedLocation, .chargingTime],
            components: components,
            sessionFee: 1,
            language: .english
        ))

        XCTAssertEqual(explanation.status, "Estimated")
        XCTAssertTrue(explanation.summary.contains("pricing rule"))
        XCTAssertTrue(explanation.evidence.contains("Matched rule: Home off-peak"))
        XCTAssertTrue(explanation.evidence.contains("Matched the saved station location"))
        XCTAssertTrue(explanation.evidence.contains("Matched the charging time window"))
        XCTAssertTrue(explanation.evidence.contains("Calculated from 2 time-based rate segments."))
        XCTAssertTrue(explanation.evidence.contains("Pricing energy: 10.00 kWh"))
        XCTAssertTrue(explanation.evidence.contains("Includes a session fee."))
    }

    func testHistoricalReferenceExplanationCannotBeMistakenForCurrentTariff() throws {
        let explanation = try XCTUnwrap(ChargeCostExplanationBuilder.build(
            source: .pricingRule,
            ruleName: "湖南居民电动汽车历史参考电价",
            matchFactors: [.regionalTariff, .historicalReference, .chargingTime],
            components: [],
            sessionFee: 0,
            language: .chinese
        ))

        XCTAssertEqual(explanation.status, "历史参考")
        XCTAssertTrue(explanation.summary.contains("已到期"))
        XCTAssertTrue(explanation.summary.contains("仅供参考"))
        XCTAssertTrue(explanation.evidence.contains {
            $0.contains("已到期") && $0.contains("核对")
        })
        XCTAssertTrue(explanation.allowsCorrection)
    }

    func testMissingCostHasNoMisleadingExplanation() {
        XCTAssertNil(ChargeCostExplanationBuilder.build(
            source: .none,
            ruleName: nil,
            matchFactors: [],
            components: [],
            sessionFee: 0,
            language: .english
        ))
    }
}
