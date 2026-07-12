import XCTest
@testable import MateDroidIOS

final class AppRouteTests: XCTestCase {
    func testEveryAndroidDestinationHasAnIOSRoute() {
        let expected: Set<AppRoute> = [
            .settings,
            .dashboard,
            .palettePreview,
            .charges(carId: 1, exteriorColor: "PPSW"),
            .chargeDetail(carId: 1, chargeId: 2, exteriorColor: "PPSW"),
            .compareCharges(carId: 1, baseChargeId: 2, exteriorColor: "PPSW"),
            .currentCharge(carId: 1, exteriorColor: "PPSW"),
            .activities(carId: 1, exteriorColor: "PPSW"),
            .places(carId: 1),
            .achievements(carId: 1, exteriorColor: "PPSW"),
            .drives(carId: 1, exteriorColor: "PPSW"),
            .driveDetail(carId: 1, driveId: 3, exteriorColor: "PPSW"),
            .compareDrives(carId: 1, baseDriveId: 3, exteriorColor: "PPSW"),
            .battery(carId: 1, efficiency: 140.5, exteriorColor: "PPSW"),
            .mileage(carId: 1, exteriorColor: "PPSW", targetDay: "2026-07-01"),
            .updates(carId: 1, exteriorColor: "PPSW"),
            .stats(carId: 1, exteriorColor: "PPSW"),
            .driveInsights(carId: 1, exteriorColor: "PPSW"),
            .countriesVisited(carId: 1, exteriorColor: "PPSW", year: 2026),
            .regionsVisited(carId: 1, countryCode: "IT", countryName: "Italy", exteriorColor: "PPSW", year: 2026),
            .whereWasI(carId: 1, timestamp: "2026-07-01T12:00:00Z", exteriorColor: "PPSW"),
            .trips(carId: 1, exteriorColor: "PPSW"),
            .createTrip(carId: 1, exteriorColor: "PPSW"),
            .tripDetail(carId: 1, tripStartDate: "2026-07-01T12:00:00Z", exteriorColor: "PPSW"),
            .sentryHistory(carId: 1, exteriorColor: "PPSW")
        ]

        XCTAssertEqual(expected.count, 25)
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

    func testDashboardMakesTopLevelHistoryFeaturesReachable() {
        let routes = DashboardNavigation.items(carId: 7, exteriorColor: "PPSW").map(\.route)

        XCTAssertTrue(routes.contains(.charges(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.drives(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.battery(carId: 7, efficiency: nil, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.mileage(carId: 7, exteriorColor: "PPSW", targetDay: nil)))
        XCTAssertTrue(routes.contains(.updates(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.achievements(carId: 7, exteriorColor: "PPSW")))
        XCTAssertTrue(routes.contains(.places(carId: 7)))
        XCTAssertTrue(routes.contains(.commuteRoutes(carId: 7)))
        XCTAssertTrue(routes.contains(.recentDrivingMap(carId: 7, exteriorColor: "PPSW")))
    }
}
