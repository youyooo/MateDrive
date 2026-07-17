import XCTest
@testable import MateDroidIOS

final class RootTabNavigationTests: XCTestCase {
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
