import XCTest
@testable import MateDriveApp

final class AppRouteTests: XCTestCase {
    func testReleaseRouteInventoryCoversEveryDestinationKind() {
        let routes = Set(RouteCoverage.allReleaseRoutes)

        XCTAssertEqual(routes.count, 33)
        XCTAssertTrue(routes.allSatisfy(RouteCoverage.hasImplementedDestination))
        XCTAssertFalse(routes.contains(.palettePreview))
        XCTAssertTrue(routes.contains(.energyCycles(carId: 1, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.activitySession(carId: 1, sessionId: "session-1")))
        XCTAssertTrue(routes.contains(.driveMetricDetail(
            carId: 1,
            driveId: 3,
            metric: .energy,
            exteriorColor: "PPSW"
        )))
        XCTAssertTrue(routes.contains(.costReview(carId: 1, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.whereWasI(
            carId: 1,
            timestamp: "2026-07-01T12:00:00Z",
            exteriorColor: "PPSW"
        )))
    }

    func testDriveMetricDetailRouteHasImplementedDestination() {
        let route = AppRoute.driveMetricDetail(
            carId: 1,
            driveId: 3,
            metric: .energy,
            exteriorColor: "PPSW"
        )

        XCTAssertTrue(RouteCoverage.hasImplementedDestination(route))
        XCTAssertEqual(route.title, "Energy Detail")
    }

    func testRouteTitleCanFollowInAppChineseLanguage() {
        XCTAssertEqual(AppRoute.currentCharge(carId: 1, exteriorColor: nil).title(language: .chinese), "当前充电")
        XCTAssertEqual(AppRoute.activities(carId: 1, exteriorColor: nil).title(language: .chinese), "活动")
        XCTAssertEqual(AppRoute.places(carId: 1).title(language: .chinese), "地点洞察")
        XCTAssertEqual(AppRoute.achievements(carId: 1, exteriorColor: nil).title(language: .chinese), "成就")
        XCTAssertEqual(AppRoute.driveInsights(carId: 1, exteriorColor: nil).title(language: .chinese), "行程洞察")
        XCTAssertEqual(AppRoute.commuteRoutes(carId: 1).title(language: .chinese), "通勤路线")
        XCTAssertEqual(AppRoute.drivingRecords(carId: 1, exteriorColor: nil).title(language: .chinese), "驾驶纪录")
        XCTAssertEqual(AppRoute.recentDrivingMap(carId: 1, exteriorColor: nil).title(language: .chinese), "近期行驶地图")
        XCTAssertEqual(AppRoute.driveMetricDetail(carId: 1, driveId: 2, metric: .energy, exteriorColor: nil).title(language: .chinese), "能量详情")
        XCTAssertEqual(AppRoute.driveMetricDetail(carId: 1, driveId: 2, metric: .energy, exteriorColor: nil).title(language: .english), "Energy Detail")
        XCTAssertEqual(AppRoute.costReview(carId: 1, exteriorColor: nil).title(language: .chinese), "用车成本回顾")
    }

    func testFeatureHubMakesTopLevelHistoryFeaturesReachable() {
        let routes = FeatureHubCatalog.sections(carId: 7, exteriorColor: "PPSW")
            .flatMap(\.items)
            .map(\.route)

        XCTAssertTrue(routes.contains(.charges(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.drives(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.battery(carId: 7, efficiency: nil, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.mileage(carId: 7, exteriorColor: "PPSW", targetDay: nil)))
        XCTAssertTrue(routes.contains(.updates(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.achievements(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.places(carId: 7)))
        XCTAssertTrue(routes.contains(.commuteRoutes(carId: 7)))
        XCTAssertTrue(routes.contains(.recentDrivingMap(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.energyCycles(carId: 7, exteriorColor: "PPSW")))
    }
}
