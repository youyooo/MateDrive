import XCTest
@testable import MateDriveApp

@MainActor
final class NavigationPerformanceTrackerTests: XCTestCase {
    func testCompletesKnownRouteWithinBudgetWithoutLoggingIdentifiers() {
        let clock = MutablePerformanceClock(now: 10)
        var results: [NavigationPerformanceResult] = []
        let route = AppRoute.driveDetail(carId: 42, driveId: 987_654, exteriorColor: "private-color")
        let tracker = NavigationPerformanceTracker(
            budget: 0.5,
            emitsSignposts: false,
            now: { clock.now },
            onCompleted: { results.append($0) }
        )

        tracker.begin(route)
        clock.now = 10.125
        tracker.destinationAppeared(route)

        XCTAssertEqual(results, [
            NavigationPerformanceResult(
                routeName: "DriveDetail",
                duration: 0.125,
                exceededBudget: false
            )
        ])
        XCTAssertFalse(route.performanceName.contains("42"))
        XCTAssertFalse(route.performanceName.contains("987654"))
        XCTAssertFalse(route.performanceName.contains("private"))
    }

    func testMarksSlowNavigationAndIgnoresUnmatchedAppearance() {
        let clock = MutablePerformanceClock(now: 20)
        var results: [NavigationPerformanceResult] = []
        let tracker = NavigationPerformanceTracker(
            budget: 0.5,
            emitsSignposts: false,
            now: { clock.now },
            onCompleted: { results.append($0) }
        )

        tracker.destinationAppeared(.charges(carId: 1, exteriorColor: nil))
        tracker.begin(.charges(carId: 1, exteriorColor: nil))
        clock.now = 20.75
        tracker.destinationAppeared(.charges(carId: 1, exteriorColor: nil))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.routeName, "Charges")
        XCTAssertEqual(results.first?.duration, 0.75)
        XCTAssertEqual(results.first?.exceededBudget, true)
    }
}

@MainActor
private final class MutablePerformanceClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}
