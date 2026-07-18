import XCTest
@testable import MateDroidIOS

final class RootTabNavigationTests: XCTestCase {
    func testActivityOwnsIndependentPath() {
        var state = RootNavigationState(
            homePath: [.dashboard],
            featuresPath: [.charges(carId: 1, exteriorColor: nil)]
        )

        state.open(.activitySession(carId: 1, sessionId: "park-10"), source: .activity)

        XCTAssertEqual(state.selectedTab, .activity)
        XCTAssertEqual(
            state.activityPath,
            [.activitySession(carId: 1, sessionId: "park-10")]
        )
        XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
    }

    func testSelectingActivityPreservesItsDetailPath() {
        let route = AppRoute.activitySession(carId: 1, sessionId: "park-10")
        var state = RootNavigationState(activityPath: [route])

        state.selectTab(.activity)

        XCTAssertEqual(state.selectedTab, .activity)
        XCTAssertEqual(state.activityPath, [route])
    }

    func testInitializerRemainsSourceCompatibleWithoutActivityPath() {
        let state = RootNavigationState(
            selectedTab: .features,
            homePath: [.dashboard],
            featuresPath: [.charges(carId: 1, exteriorColor: nil)],
            settingsPath: [.palettePreview]
        )

        XCTAssertTrue(state.activityPath.isEmpty)
        XCTAssertEqual(state.selectedTab, .features)
    }

    func testActivitySessionRouteHasLocalizedTitlesAndCoverage() {
        let route = AppRoute.activitySession(carId: 1, sessionId: "park-10")

        XCTAssertEqual(route.title(language: .english), "Activity Detail")
        XCTAssertEqual(route.title(language: .chinese), "活动详情")
        XCTAssertTrue(RouteCoverage.hasImplementedDestination(route))
    }

    func testSelectingSettingsClearsRetainedChildPath() {
        var state = RootNavigationState(
            selectedTab: .features,
            settingsPath: [.palettePreview]
        )

        state.selectTab(.settings)

        XCTAssertEqual(state.selectedTab, .settings)
        XCTAssertTrue(state.settingsPath.isEmpty)
    }

    func testDashboardAndSettingsSelectTheirRootTabs() {
        var state = RootNavigationState()
        state.open(.charges(carId: 1, exteriorColor: nil), source: .features)

        state.open(.dashboard, source: .features)

        XCTAssertEqual(state.selectedTab, .home)
        XCTAssertTrue(state.homePath.isEmpty)

        state.open(.settings, source: .home)

        XCTAssertEqual(state.selectedTab, .settings)
        XCTAssertTrue(state.settingsPath.isEmpty)
    }

    func testFeatureShortcutPreservesHomePath() {
        var state = RootNavigationState()
        state.open(.mileage(carId: 1, exteriorColor: nil, targetDay: nil), source: .home)

        state.openShortcut(.charges(carId: 1, exteriorColor: nil))

        XCTAssertEqual(state.selectedTab, .features)
        XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
        XCTAssertEqual(
            state.homePath,
            [.mileage(carId: 1, exteriorColor: nil, targetDay: nil)]
        )
    }

    func testRoutesAppendOnlyToTheirSourceStack() {
        var state = RootNavigationState()

        state.open(.drives(carId: 1, exteriorColor: nil), source: .home)
        state.open(.charges(carId: 1, exteriorColor: nil), source: .features)
        state.open(.palettePreview, source: .settings)

        XCTAssertEqual(state.homePath, [.drives(carId: 1, exteriorColor: nil)])
        XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
        XCTAssertEqual(state.settingsPath, [.palettePreview])
        XCTAssertEqual(state.selectedTab, .settings)
    }

    func testDashboardShortcutClearsOnlyHomeStack() {
        var state = RootNavigationState(
            selectedTab: .features,
            homePath: [.drives(carId: 1, exteriorColor: nil)],
            featuresPath: [.charges(carId: 1, exteriorColor: nil)],
            settingsPath: [.palettePreview]
        )

        state.openShortcut(.dashboard)

        XCTAssertEqual(state.selectedTab, .home)
        XCTAssertTrue(state.homePath.isEmpty)
        XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
        XCTAssertEqual(state.settingsPath, [.palettePreview])
    }
}
