import XCTest
@testable import MateDroidIOS

final class RouteCoverageTests: XCTestCase {
    func testAllRoutesHaveImplementedDestinations() {
        XCTAssertEqual(RouteCoverage.allAndroidRoutes.count, 30)
        XCTAssertTrue(RouteCoverage.allAndroidRoutes.allSatisfy { RouteCoverage.hasImplementedDestination($0) })
    }

    func testRouteCoverageContainsNoDuplicateDestinations() {
        XCTAssertEqual(Set(RouteCoverage.allAndroidRoutes).count, RouteCoverage.allAndroidRoutes.count)
    }
}
