import XCTest
@testable import MateDroidIOS

final class RegionalChargingTariffTests: XCTestCase {
    func testCatalogContainsEveryMainlandProvincialRegionCode() throws {
        let catalog = try RegionalChargingTariffCatalog.load()

        XCTAssertEqual(Set(catalog.regions.map(\.regionCode)), Set([
            "CN-11", "CN-12", "CN-13", "CN-14", "CN-15",
            "CN-21", "CN-22", "CN-23", "CN-31", "CN-32", "CN-33", "CN-34", "CN-35", "CN-36", "CN-37",
            "CN-41", "CN-42", "CN-43", "CN-44", "CN-45", "CN-46",
            "CN-50", "CN-51", "CN-52", "CN-53", "CN-54",
            "CN-61", "CN-62", "CN-63", "CN-64", "CN-65"
        ]))
    }

    func testExpiredHunanPilotIsHistoricalForNewCharges() throws {
        let catalog = try RegionalChargingTariffCatalog.load()
        let historicalDate = try XCTUnwrap(DomainDateParser.date(from: "2025-06-30T12:00:00+08:00"))
        let currentDate = try XCTUnwrap(DomainDateParser.date(from: "2026-07-18T12:00:00+08:00"))

        XCTAssertNotNil(catalog.entry(regionCode: "CN-43", date: historicalDate))
        XCTAssertNil(catalog.entry(regionCode: "CN-43", date: currentDate))
    }

    func testHunanHistoricalEntryMakesACompletePricingRule() throws {
        let catalog = try RegionalChargingTariffCatalog.load()
        let date = try XCTUnwrap(DomainDateParser.date(from: "2025-06-30T12:00:00+08:00"))
        let entry = try XCTUnwrap(catalog.entry(regionCode: "CN-43", date: date))

        let rule = catalog.makePricingRule(regionCode: "CN-43", from: entry)

        XCTAssertEqual(rule.id, entry.id)
        XCTAssertEqual(rule.chargeType, .ac)
        XCTAssertEqual(rule.pricePerKWh, 0.604)
        XCTAssertEqual(rule.timeSegments.count, 5)
        XCTAssertEqual(rule.effectiveFromDate, "2024-07-01")
        XCTAssertEqual(rule.effectiveToDate, "2025-06-30")
        XCTAssertEqual(rule.origin, .regionalOfficial)
        XCTAssertEqual(rule.regionCode, "CN-43")
        XCTAssertEqual(rule.sourceURL, entry.sourceURL.absoluteString)
        XCTAssertEqual(rule.verifiedAt, "2026-07-18")
        XCTAssertEqual(rule.serviceFeePerKWh, entry.serviceFeePerKWh)
        XCTAssertEqual(rule.applicableWeekdays, entry.applicableWeekdays)
        XCTAssertEqual(rule.applicableMonths, entry.applicableMonths)
    }

    func testPricingRuleConversionKeepsFeesApplicabilityAndProvenanceSeparate() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://fgw.hunan.gov.cn/policy"))
        let entry = RegionalChargingTariff(
            id: "seasonal",
            status: .historical,
            customerClass: "residential-ev",
            chargeType: .ac,
            currencyCode: "CNY",
            effectiveFromDate: "2025-06-01",
            effectiveToDate: "2025-08-31",
            documentID: "audited-document",
            sourceURL: sourceURL,
            basePricePerKWh: 0.5,
            timeSegments: [
                ChargePricingTimeSegment(
                    id: "all-day",
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 1_439,
                    pricePerKWh: 0.4
                )
            ],
            serviceFeePerKWh: 0.2,
            sessionFee: 1,
            applicableWeekdays: [2, 3, 4, 5, 6],
            applicableMonths: [6, 7, 8]
        )
        let catalog = RegionalChargingTariffCatalog(
            version: 1,
            generatedAt: "2026-07-18",
            regions: [
                RegionalChargingTariffRegion(
                    regionCode: "CN-43",
                    names: ["en": "Hunan"],
                    availability: .verified,
                    verifiedAt: "2026-07-18",
                    tariffs: [entry]
                )
            ]
        )

        let rule = catalog.makePricingRule(regionCode: "CN-43", from: entry)

        XCTAssertEqual(rule.pricePerKWh, 0.5)
        XCTAssertEqual(rule.timeSegments.first?.pricePerKWh, 0.4)
        XCTAssertEqual(rule.serviceFeePerKWh, 0.2)
        XCTAssertEqual(rule.applicableWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(rule.applicableMonths, [6, 7, 8])
        XCTAssertEqual(rule.origin, .regionalOfficial)
        XCTAssertEqual(rule.regionCode, "CN-43")
        XCTAssertEqual(rule.sourceURL, sourceURL.absoluteString)
        XCTAssertEqual(rule.verifiedAt, "2026-07-18")
    }

    func testPricingRuleRoundTripPreservesRegionalApplicabilityAndProvenance() throws {
        let rule = ChargePricingRule(
            id: "regional",
            name: "Regional",
            chargeType: .ac,
            effectiveFromDate: "2025-01-01",
            effectiveToDate: "2025-12-31",
            pricePerKWh: 0.5,
            origin: .regionalOfficial,
            regionCode: "CN-43",
            sourceURL: "https://fgw.hunan.gov.cn/policy",
            verifiedAt: "2026-07-18",
            serviceFeePerKWh: 0.2,
            applicableWeekdays: [2, 3, 4, 5, 6],
            applicableMonths: [6, 7, 8]
        )

        let decoded = try JSONDecoder().decode(
            ChargePricingRule.self,
            from: JSONEncoder().encode(rule)
        )

        XCTAssertEqual(decoded, rule)
    }

    func testLegacyPricingRuleDecodingUsesBackwardCompatibleDefaults() throws {
        let data = try XCTUnwrap(#"{"id":"legacy","name":"Legacy","pricePerKWh":0.6}"#.data(using: .utf8))

        let rule = try JSONDecoder().decode(ChargePricingRule.self, from: data)

        XCTAssertEqual(rule.origin, .user)
        XCTAssertNil(rule.regionCode)
        XCTAssertNil(rule.sourceURL)
        XCTAssertNil(rule.verifiedAt)
        XCTAssertEqual(rule.serviceFeePerKWh, 0)
        XCTAssertNil(rule.applicableWeekdays)
        XCTAssertNil(rule.applicableMonths)
    }

    func testPricingRuleValidationRejectsInvalidRegionalFields() {
        let rule = ChargePricingRule(
            name: "Invalid regional rule",
            pricePerKWh: 0.5,
            serviceFeePerKWh: -0.1,
            applicableWeekdays: [0],
            applicableMonths: [13]
        )

        let issues = ChargePricingRuleValidator.issues(for: rule)

        XCTAssertTrue(issues.contains(.invalidServiceFee))
        XCTAssertTrue(issues.contains(.invalidApplicableWeekdays))
        XCTAssertTrue(issues.contains(.invalidApplicableMonths))
    }

    func testPricingRuleMatchesWeekdayAndMonthInShanghaiForEquivalentInstants() {
        let rule = ChargePricingRule(
            name: "Shanghai Tuesday in July",
            pricePerKWh: 0.5,
            applicableWeekdays: [3],
            applicableMonths: [7]
        )

        for timestamp in ["2025-06-30T16:00:00Z", "2025-07-01T00:00:00+08:00"] {
            let input = ChargePricingInput(
                startDate: timestamp,
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 1,
                isDc: false
            )
            XCTAssertNotNil(ChargePricingRuleEngine.estimateCost(for: input, rules: [rule]), timestamp)
        }

        let mondayRule = ChargePricingRule(
            name: "Shanghai Monday in July",
            pricePerKWh: 0.5,
            applicableWeekdays: [2],
            applicableMonths: [7]
        )
        let input = ChargePricingInput(
            startDate: "2025-06-30T16:00:00Z",
            address: nil,
            latitude: nil,
            longitude: nil,
            energyAddedKWh: 1,
            isDc: false
        )
        XCTAssertNil(ChargePricingRuleEngine.estimateCost(for: input, rules: [mondayRule]))
    }

    func testCatalogAndPricingRuleAgreeAtShanghaiEffectiveDateBoundaries() throws {
        let catalog = try RegionalChargingTariffCatalog.load()
        let ruleDate = try XCTUnwrap(DomainDateParser.date(from: "2025-06-30T12:00:00+08:00"))
        let entry = try XCTUnwrap(catalog.entry(regionCode: "CN-43", date: ruleDate))
        let rule = catalog.makePricingRule(regionCode: "CN-43", from: entry)
        let cases = [
            ("2024-06-30T15:59:59Z", false),
            ("2024-06-30T16:00:00Z", true),
            ("2024-07-01T00:00:00+08:00", true),
            ("2025-06-30T15:59:59Z", true),
            ("2025-06-30T23:59:59+08:00", true),
            ("2025-06-30T16:00:00Z", false),
            ("2025-07-01T00:00:00+08:00", false)
        ]

        for (timestamp, expectedMatch) in cases {
            let date = try XCTUnwrap(DomainDateParser.date(from: timestamp))
            let catalogMatches = catalog.entry(regionCode: "CN-43", date: date) != nil
            let input = ChargePricingInput(
                startDate: timestamp,
                address: nil,
                latitude: nil,
                longitude: nil,
                energyAddedKWh: 1,
                isDc: false
            )
            let ruleMatches = ChargePricingRuleEngine.estimateCost(for: input, rules: [rule]) != nil

            XCTAssertEqual(catalogMatches, expectedMatch, timestamp)
            XCTAssertEqual(ruleMatches, expectedMatch, timestamp)
            XCTAssertEqual(ruleMatches, catalogMatches, timestamp)
        }
    }
}
