import XCTest
@testable import MateDriveApp

final class FeatureHubCatalogTests: XCTestCase {
    func testCatalogUsesApprovedSectionAndItemOrder() {
        let sections = FeatureHubCatalog.sections(carId: 7, exteriorColor: "PPSW")

        XCTAssertEqual(sections.map(\.id), [
            "common",
            "charging-driving",
            "insights",
            "records"
        ])
        XCTAssertEqual(sections[0].items.map(\.id), [
            "current-charge", "activities", "drives", "battery"
        ])
        XCTAssertEqual(sections[1].items.map(\.id), [
            "charges", "recent-map", "trips", "energy-balance"
        ])
        XCTAssertEqual(sections[2].items.map(\.id), [
            "stats", "mileage", "places", "drive-insights",
            "environment", "standby-hotspots", "commute-routes"
        ])
        XCTAssertEqual(sections[3].items.map(\.id), [
            "achievements", "updates", "sentry"
        ])
    }

    func testCatalogBuildsEveryTopLevelRouteExactlyOnce() {
        let sections = FeatureHubCatalog.sections(carId: 7, exteriorColor: "PPSW")
        let routes = sections.flatMap(\.items).map(\.route)

        XCTAssertEqual(routes.count, 18)
        XCTAssertEqual(Set(routes).count, routes.count)
        XCTAssertTrue(routes.contains(.energyCycles(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.commuteRoutes(carId: 7)))
        XCTAssertTrue(routes.contains(.sentryHistory(carId: 7, exteriorColor: "PPSW")))
    }

    func testCatalogHasCompleteEnglishAndChinesePresentationText() {
        let sections = FeatureHubCatalog.sections(carId: 7, exteriorColor: nil)

        for section in sections {
            XCTAssertFalse(section.title(language: .english).isEmpty)
            XCTAssertFalse(section.title(language: .chinese).isEmpty)
            for item in section.items {
                XCTAssertFalse(item.title(language: .english).isEmpty)
                XCTAssertFalse(item.title(language: .chinese).isEmpty)
                XCTAssertFalse(item.subtitle(language: .english).isEmpty)
                XCTAssertFalse(item.subtitle(language: .chinese).isEmpty)
                XCTAssertFalse(item.systemImage.isEmpty)
            }
        }
    }
}
