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
    }
}
