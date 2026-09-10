import XCTest
@testable import MateDriveApp

final class MonetizationPolicyTests: XCTestCase {
    func testFirstReleaseKeepsEveryFeatureFree() {
        let policy = MonetizationPolicy.firstRelease

        for feature in MateDriveFeature.allCases {
            XCTAssertTrue(
                policy.canAccess(feature, entitlement: .none),
                "First release unexpectedly locked \(feature)"
            )
        }
    }

    func testFutureProModeOnlyLocksFeaturesMarkedAsPro() {
        let policy = MonetizationPolicy(launchMode: .proEnabled)

        XCTAssertTrue(policy.canAccess(.vehicleOverview, entitlement: .none))
        XCTAssertFalse(policy.canAccess(.advancedAnalytics, entitlement: .none))
        XCTAssertTrue(policy.canAccess(.advancedAnalytics, entitlement: .lifetime))
        XCTAssertTrue(policy.canAccess(.advancedAnalytics, entitlement: .subscription))
    }

    func testProductCatalogContainsUniqueStableProductIdentifiers() {
        let catalog = StoreProductCatalog.mateDrive

        XCTAssertEqual(catalog.productIDs.count, 3)
        XCTAssertEqual(Set(catalog.productIDs).count, catalog.productIDs.count)
        XCTAssertEqual(catalog.lifetimeID, "com.matedrive.ios.pro.lifetime")
        XCTAssertEqual(catalog.monthlyID, "com.matedrive.ios.pro.monthly")
        XCTAssertEqual(catalog.yearlyID, "com.matedrive.ios.pro.yearly")
    }

    func testEntitlementSnapshotPrefersLifetimeOverSubscription() {
        XCTAssertEqual(
            ProEntitlementSnapshot(hasLifetime: true, hasActiveSubscription: true).status,
            .lifetime
        )
        XCTAssertEqual(
            ProEntitlementSnapshot(hasLifetime: false, hasActiveSubscription: true).status,
            .subscription
        )
        XCTAssertEqual(
            ProEntitlementSnapshot(hasLifetime: false, hasActiveSubscription: false).status,
            .none
        )
    }
}
