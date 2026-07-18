import XCTest
@testable import MateDroidIOS

@MainActor
final class AppShortcutTests: XCTestCase {
    func testFeatureShortcutFromActivityKeepsActivityPathIndependent() {
        let activityRoute = AppRoute.activitySession(carId: 42, sessionId: "park-10")
        var state = RootNavigationState(
            selectedTab: .activity,
            activityPath: [activityRoute]
        )

        state.openShortcut(.drives(carId: 42, exteriorColor: nil))

        XCTAssertEqual(state.selectedTab, .features)
        XCTAssertEqual(state.featuresPath, [.drives(carId: 42, exteriorColor: nil)])
        XCTAssertEqual(state.activityPath, [activityRoute])
    }

    func testActivityTabDoesNotIntroduceANewAppShortcutDestination() {
        XCTAssertEqual(
            Set(MateDriveShortcutDestination.allCases),
            [.dashboard, .currentCharge, .charges, .drives, .activities]
        )
    }

    func testPendingShortcutStoreConsumesRequestExactlyOnce() throws {
        let suiteName = "AppShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingShortcutNavigationStore(defaults: defaults)

        store.store(.charges)

        XCTAssertEqual(store.consume(), .charges)
        XCTAssertNil(store.consume())
    }

    func testShortcutRouterUsesSelectedVehicleForFeaturePages() {
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 42
        )

        XCTAssertEqual(
            MateDriveShortcutRouter.route(destination: .currentCharge, settings: settings),
            .currentCharge(carId: 42, exteriorColor: nil)
        )
        XCTAssertEqual(
            MateDriveShortcutRouter.route(destination: .charges, settings: settings),
            .charges(carId: 42, exteriorColor: nil)
        )
        XCTAssertEqual(
            MateDriveShortcutRouter.route(destination: .drives, settings: settings),
            .drives(carId: 42, exteriorColor: nil)
        )
        XCTAssertEqual(
            MateDriveShortcutRouter.route(destination: .activities, settings: settings),
            .activities(carId: 42, exteriorColor: nil)
        )
    }

    func testShortcutRouterUsesFallbackVehicleWhenSelectionIsMissing() {
        let settings = AppSettings(serverURL: "https://teslamate.example")

        XCTAssertEqual(
            MateDriveShortcutRouter.route(
                destination: .charges,
                settings: settings,
                fallbackCarId: 7
            ),
            .charges(carId: 7, exteriorColor: nil)
        )
    }

    func testShortcutRouterFallsBackSafelyWithoutConfigurationOrVehicle() {
        XCTAssertEqual(
            MateDriveShortcutRouter.route(destination: .drives, settings: AppSettings()),
            .settings
        )
        XCTAssertEqual(
            MateDriveShortcutRouter.route(
                destination: .activities,
                settings: AppSettings(serverURL: "https://teslamate.example")
            ),
            .dashboard
        )
    }
}
