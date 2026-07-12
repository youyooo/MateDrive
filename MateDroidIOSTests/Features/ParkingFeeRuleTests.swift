import XCTest
@testable import MateDroidIOS

final class ParkingFeeRuleTests: XCTestCase {
    func testHourlyRuleAppliesFreeTimeIncrementFixedFeeAndCap() {
        let rule = ParkingFeeRule(name: "Mall", addressKeyword: "Mall", freeMinutes: 30, billingIncrementMinutes: 60, hourlyRate: 8, fixedFee: 2, sessionCap: 15)
        let estimate = ParkingFeeRuleEngine.estimate(
            for: ParkingFeeInput(startDate: "2026-07-01T10:00:00Z", address: "City Mall", latitude: nil, longitude: nil, durationMinutes: 151),
            rules: [rule]
        )

        XCTAssertEqual(estimate?.billableMinutes, 121)
        XCTAssertEqual(estimate?.billedIncrements, 3)
        XCTAssertEqual(estimate?.sessionCost, 15)
    }

    func testFreeParkingStillAppliesConfiguredFixedEntryFee() {
        let rule = ParkingFeeRule(name: "Station", freeMinutes: 60, hourlyRate: 5, fixedFee: 2)
        let estimate = ParkingFeeRuleEngine.estimate(
            for: ParkingFeeInput(startDate: nil, address: nil, latitude: nil, longitude: nil, durationMinutes: 30),
            rules: [rule]
        )
        XCTAssertEqual(estimate?.billableMinutes, 0)
        XCTAssertEqual(estimate?.sessionCost, 2)
    }

    func testMonthlyRuleIsChargedOncePerRuleAndCalendarMonth() {
        let rule = ParkingFeeRule(id: "home", name: "Home", addressKeyword: "Home", monthlyFee: 300)
        let inputs = [
            ParkingFeeInput(startDate: "2026-07-01T00:00:00Z", address: "Home", latitude: nil, longitude: nil, durationMinutes: 100),
            ParkingFeeInput(startDate: "2026-07-20T00:00:00Z", address: "Home", latitude: nil, longitude: nil, durationMinutes: 200),
            ParkingFeeInput(startDate: "2026-08-01T00:00:00Z", address: "Home", latitude: nil, longitude: nil, durationMinutes: 100),
            ParkingFeeInput(startDate: "2026-08-01T00:00:00Z", address: "Elsewhere", latitude: nil, longitude: nil, durationMinutes: 100)
        ]

        let summary = ParkingFeeRuleEngine.summarize(inputs, rules: [rule])

        XCTAssertEqual(summary.sessionCost, 0)
        XCTAssertEqual(summary.recurringMonthlyCost, 600)
        XCTAssertEqual(summary.totalCost, 600)
        XCTAssertEqual(summary.matchedParkingCount, 3)
        XCTAssertEqual(summary.unmatchedParkingCount, 1)
    }

    func testMonthlyAndPureFixedRulesDoNotRequireParkingDuration() {
        let input = ParkingFeeInput(startDate: "2026-07-01T00:00:00Z", address: "Garage", latitude: nil, longitude: nil, durationMinutes: nil)
        let monthly = ParkingFeeRule(name: "Monthly", monthlyFee: 300)
        let fixed = ParkingFeeRule(name: "Fixed", hourlyRate: 0, fixedFee: 8, priority: 10)

        XCTAssertTrue(ParkingFeeRuleEngine.estimate(for: input, rules: [monthly])?.usesMonthlyFee == true)
        XCTAssertEqual(ParkingFeeRuleEngine.estimate(for: input, rules: [fixed])?.sessionCost, 8)
    }

    func testLocationAndPrioritySelectMostSpecificValidRule() {
        let fallback = ParkingFeeRule(id: "fallback", name: "Fallback", hourlyRate: 2)
        let nearby = ParkingFeeRule(id: "nearby", name: "Nearby", latitude: 28.2, longitude: 112.8, radiusMeters: 300, hourlyRate: 5, priority: 10)
        let estimate = ParkingFeeRuleEngine.estimate(
            for: ParkingFeeInput(startDate: nil, address: nil, latitude: 28.2005, longitude: 112.8005, durationMinutes: 60),
            rules: [fallback, nearby]
        )
        XCTAssertEqual(estimate?.rule.id, "nearby")
        XCTAssertEqual(estimate?.sessionCost, 5)
    }

    func testValidatorRejectsUnsafeOrEmptyRules() {
        let rule = ParkingFeeRule(name: "", latitude: 91, longitude: 1, radiusMeters: -1, freeMinutes: -1, billingIncrementMinutes: 0, hourlyRate: -.infinity, fixedFee: -1, sessionCap: -1, monthlyFee: -1)
        let issues = ParkingFeeRuleValidator.issues(for: rule)
        XCTAssertTrue(issues.contains(.emptyName))
        XCTAssertTrue(issues.contains(.invalidLocation))
        XCTAssertTrue(issues.contains(.invalidFreeMinutes))
        XCTAssertTrue(issues.contains(.invalidIncrement))
        XCTAssertTrue(issues.contains(.invalidHourlyRate))
        XCTAssertTrue(issues.contains(.invalidFixedFee))
        XCTAssertTrue(issues.contains(.invalidSessionCap))
        XCTAssertTrue(issues.contains(.invalidMonthlyFee))
    }

    func testOldSettingsDecodeWithEmptyParkingRules() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"serverURL":"https://example.test"}"#.utf8))
        XCTAssertTrue(settings.parkingFeeRules.isEmpty)
    }

    func testSettingsRoundTripPreservesParkingRuleFields() throws {
        let rule = ParkingFeeRule(
            id: "garage", name: "Garage", addressKeyword: "Office", latitude: 28.2, longitude: 112.8,
            radiusMeters: 250, freeMinutes: 20, billingIncrementMinutes: 30, hourlyRate: 6,
            fixedFee: 1, sessionCap: 25, monthlyFee: 400, priority: 9
        )
        let original = AppSettings(serverURL: "https://example.test", currencyCode: "CNY", parkingFeeRules: [rule])

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(restored.parkingFeeRules, [rule])
        XCTAssertEqual(restored.currencyCode, "CNY")
    }
}
