import XCTest
@testable import MateDroidIOS

final class ActivityPurposeClassifierTests: XCTestCase {
    func testSessionOverrideWinsOverGeofenceAndHeuristics() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            sessionOverride: .fixture(purpose: .pickupDropoff),
            geofenceKind: .work,
            recurrenceCount: 20,
            hasCharge: true
        ))

        XCTAssertEqual(result.purpose, .pickupDropoff)
        XCTAssertEqual(result.source, .userSession)
        XCTAssertEqual(result.confidence, 1)
        XCTAssertEqual(result.reasons, [.confirmedOverride])
    }

    func testPlaceOverrideWinsOverGeofence() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            placeOverride: .fixture(purpose: .custom),
            geofenceKind: .shopping,
            recurrenceCount: 4
        ))

        XCTAssertEqual(result.purpose, .custom)
        XCTAssertEqual(result.source, .userPlaceRule)
        XCTAssertEqual(result.confidence, 1)
    }

    func testHomeACLateChargeExplainsHomeCharging() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .home,
            chargeIdentity: .ac,
            chargeStartMinute: 23 * 60,
            hasCharge: true
        ))

        XCTAssertEqual(result.purpose, .homeCharging)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.8)
        XCTAssertTrue(result.reasons.contains(.homeGeofence))
        XCTAssertTrue(result.reasons.contains(.acCharging))
    }

    func testGeofenceClassifiesEverySupportedConfiguredPurpose() {
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .charging, hasCharge: true)).purpose, .replenishment)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .home, hasCharge: true)).purpose, .homeCharging)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .work, hasCharge: true)).purpose, .workCharging)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .shopping)).purpose, .shopping)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .schoolPickup)).purpose, .pickupDropoff)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .parking)).purpose, .parking)
    }

    func testConfirmedCommuteOutranksGenericHeuristicButNotUserOverride() {
        let commute = ActivityPurposeClassifier.classify(.fixture(
            recurrenceCount: 4,
            isConfirmedCommute: true
        ))
        let override = ActivityPurposeClassifier.classify(.fixture(
            sessionOverride: .fixture(purpose: .shopping),
            isConfirmedCommute: true
        ))

        XCTAssertEqual(commute.purpose, .commute)
        XCTAssertEqual(override.purpose, .shopping)
        XCTAssertEqual(override.source, .userSession)
    }

    func testRepeatedPatternAndPromptDepartureAreDeterministic() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            recurrenceCount: 4,
            hasCharge: true,
            hasPromptDeparture: true
        ))

        XCTAssertEqual(result.purpose, .replenishment)
        XCTAssertEqual(result.source, .learnedPattern)
        XCTAssertEqual(result.confidence, 0.85)
        XCTAssertEqual(result.reasons, [.repeatedTimeWindow, .promptDeparture])
    }

    func testLowEvidenceRemainsUnclassified() {
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture()).purpose, .unclassified)
    }

    func testCustomPresentationUsesStoredNameAndFixedPurposesAreLocalized() {
        XCTAssertEqual(SmartActivityPurpose.custom.title(language: .english, customName: "Gym"), "Gym")
        XCTAssertEqual(SmartActivityPurpose.shopping.title(language: .chinese), "购物")
        XCTAssertEqual(SmartActivityPurpose.pickupDropoff.systemImage, "figure.2.and.child.holdinghands")
    }

    func testReconstructionAppliesMatchingSessionOverrideWithoutChangingSources() {
        let parking = TeslaMateActivity(
            id: 1,
            type: "park",
            startDate: "2026-07-18T10:00:00Z",
            endDate: "2026-07-18T11:00:00Z"
        )
        let override = ActivityLabelOverride(
            id: "confirmed",
            carId: 1,
            sessionId: "1-1",
            placeKey: nil,
            scope: .sessionOnly,
            purpose: .custom,
            customName: "Gym",
            icon: "tag",
            colorHex: "#000000",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        let session = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking],
            sleepIntervals: [],
            geofences: [],
            labelOverrides: [override]
        ).first

        XCTAssertEqual(session?.classification?.purpose, .custom)
        XCTAssertEqual(session?.classification?.source, .userSession)
        XCTAssertEqual(session?.eventReferences.map(\.sourceID), [1])
    }
}

private extension ActivityClassificationInput {
    static func fixture(
        sessionOverride: ActivityLabelOverride? = nil,
        placeOverride: ActivityLabelOverride? = nil,
        geofenceKind: GeofenceKind? = nil,
        recurrenceCount: Int = 0,
        chargeIdentity: ChargePricingChargerIdentity? = nil,
        chargeStartMinute: Int? = nil,
        hasCharge: Bool = false,
        hasPromptDeparture: Bool = false,
        isConfirmedCommute: Bool = false
    ) -> ActivityClassificationInput {
        ActivityClassificationInput(
            session: .fixture(),
            sessionOverride: sessionOverride,
            placeOverride: placeOverride,
            geofenceKind: geofenceKind,
            recurrenceCount: recurrenceCount,
            chargeIdentity: chargeIdentity,
            chargeStartMinute: chargeStartMinute,
            hasCharge: hasCharge,
            hasPromptDeparture: hasPromptDeparture,
            isConfirmedCommute: isConfirmedCommute
        )
    }
}

private extension SmartActivitySession {
    static func fixture() -> SmartActivitySession {
        SmartActivitySession(
            id: "session",
            carId: 1,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: nil,
            placeKey: "place",
            latitude: nil,
            longitude: nil,
            geofenceID: nil,
            provisionalKind: .unclassified,
            classification: nil,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: [],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "source",
            derivationFingerprint: "derived"
        )
    }
}

private extension ActivityLabelOverride {
    static func fixture(purpose: SmartActivityPurpose) -> ActivityLabelOverride {
        ActivityLabelOverride(
            id: "override-\(purpose.rawValue)",
            carId: 1,
            sessionId: "session",
            placeKey: "place",
            scope: .sessionOnly,
            purpose: purpose,
            customName: nil,
            icon: "tag",
            colorHex: "#000000",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
