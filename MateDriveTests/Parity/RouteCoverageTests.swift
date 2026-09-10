import XCTest
@testable import MateDriveApp

final class RouteCoverageTests: XCTestCase {
    func testAllRoutesHaveImplementedDestinations() {
        XCTAssertEqual(RouteCoverage.allReleaseRoutes.count, 33)
        XCTAssertTrue(RouteCoverage.allReleaseRoutes.allSatisfy { RouteCoverage.hasImplementedDestination($0) })
        XCTAssertFalse(RouteCoverage.allReleaseRoutes.contains(.palettePreview))
    }

    func testRouteCoverageContainsNoDuplicateDestinations() {
        XCTAssertEqual(Set(RouteCoverage.allReleaseRoutes).count, RouteCoverage.allReleaseRoutes.count)
    }
}
