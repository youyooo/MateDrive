import XCTest
@testable import MateDroidIOS

final class TeslaMateCapabilityPresentationTests: XCTestCase {
    func testEnhancedFeatureMinimumRequires25OrNewer() {
        XCTAssertEqual(TeslaMateCapabilityPresentation.enhancedFeatureMinimumDisplayVersion, "2.5")
        XCTAssertFalse(TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: "2.4.1", buildInfo: nil)) ?? true)
        XCTAssertTrue(TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: "2.5.0", buildInfo: nil)) ?? false)
        XCTAssertTrue(TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: "2.5.1", buildInfo: nil)) ?? false)
        XCTAssertTrue(TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: "2.6.0", buildInfo: nil)) ?? false)
        XCTAssertNil(TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(TeslaMateVersionInfo(apiVersion: "unknown", mtAPIVersion: nil, buildInfo: nil)))
    }
    func testVisibleCapabilitiesHaveStableOrder() {
        XCTAssertEqual(TeslaMateCapabilityPresentation.visibleCapabilities, [
            .serverStats, .costReview, .unifiedActivities, .batteryHealthHistory, .driveInsights, .environmentHistory, .topDrainLocations, .commuteRoutes, .statsExtremes, .drivingCoordinates, .serverPlaces
        ])
    }

    func testEveryCapabilityStateHasAnIconAndLocalizationKey() {
        for state in [TeslaMateCapabilityState.available, .degraded, .unavailable, .unknown] {
            XCTAssertFalse(TeslaMateCapabilityPresentation.icon(for: state).isEmpty)
            XCTAssertFalse(TeslaMateCapabilityPresentation.stateLocalizationKey(for: state).isEmpty)
        }
    }
}
