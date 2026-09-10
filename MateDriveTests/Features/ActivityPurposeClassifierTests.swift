import XCTest
@testable import MateDriveApp

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
            placeOverride: .fixture(purpose: .custom, scope: .futureAtPlace),
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
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .garage)).purpose, .parking)
        XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture(geofenceKind: .park)).purpose, .leisure)
    }

    func testRepeatedWeekdayWorkArrivalIsClassifiedAsCommute() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .work,
            recurrenceCount: 4,
            arrivalMinute: 8 * 60 + 30,
            isWeekday: true,
            dwellMinutes: 8 * 60
        ))

        XCTAssertEqual(result.purpose, .commute)
        XCTAssertTrue(result.reasons.contains(.weekdayTimeWindow))
        XCTAssertTrue(result.reasons.contains(.repeatedTimeWindow))
    }

    func testWeekendWorkVisitDoesNotPretendToBeCommute() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .work,
            recurrenceCount: 4,
            arrivalMinute: 8 * 60 + 30,
            isWeekday: false
        ))

        XCTAssertEqual(result.purpose, .parking)
    }

    func testPromptDCChargeAtShoppingGeofenceIsReplenishment() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .shopping,
            chargeIdentity: .unknownDC,
            hasCharge: true,
            hasPromptDeparture: true,
            dwellMinutes: 35
        ))

        XCTAssertEqual(result.purpose, .replenishment)
        XCTAssertEqual(result.reasons.filter { $0 == .promptDeparture }.count, 1)
    }

    func testLongACStayAtShoppingGeofenceRemainsShopping() {
        let result = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .shopping,
            chargeIdentity: .ac,
            hasCharge: true,
            dwellMinutes: 180
        ))

        XCTAssertEqual(result.purpose, .shopping)
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
        XCTAssertEqual(result.confidence, 0.85, accuracy: 0.000_001)
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

    func testUnknownGeofenceKindDegradesToOtherWithoutDiscardingSettings() throws {
        let coordinate = SyntheticCoordinates.point()
        let data = Data(
            """
            {
              "serverURL": "https://teslamate.example",
              "geofenceRules": [{
                "id": "future-kind",
                "carId": 7,
                "name": "Future venue",
                "kind": "futureVenue",
                "latitude": \(coordinate.northing),
                "longitude": \(coordinate.easting),
                "radiusMeters": 120,
                "isEnabled": true,
                "participatesInCommuteClassification": true
              }]
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let rules = try XCTUnwrap(object["geofenceRules"] as? [[String: Any]])

        XCTAssertEqual(settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(settings.geofenceRules.first?.kind, .other)
        XCTAssertEqual(rules.first?["kind"] as? String, "other")
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(GeofenceKind.shopping), as: UTF8.self), "\"shopping\"")
    }

    func testClassificationExplanationDistinguishesSuggestionFromConfirmation() {
        let suggested = ActivityPurposeClassifier.classify(.fixture(
            geofenceKind: .work,
            recurrenceCount: 4,
            arrivalMinute: 8 * 60 + 30,
            isWeekday: true
        ))
        let suggestedExplanation = ActivityClassificationExplanationBuilder.build(
            suggested,
            language: .chinese
        )

        XCTAssertFalse(suggestedExplanation.isUserConfirmed)
        XCTAssertEqual(suggestedExplanation.status, "围栏匹配")
        XCTAssertEqual(suggestedExplanation.confidenceText, "可信度 95%")
        XCTAssertTrue(suggestedExplanation.evidence.contains("位于已保存的公司围栏内"))
        XCTAssertTrue(suggestedExplanation.evidence.contains("符合工作日通勤时段"))
        XCTAssertTrue(suggestedExplanation.evidence.contains("匹配到重复路线"))
        XCTAssertTrue(suggestedExplanation.evidence.contains("多次出现在相近时段"))

        let confirmed = ActivityPurposeClassifier.classify(.fixture(
            sessionOverride: .fixture(purpose: .commute)
        ))
        let confirmedExplanation = ActivityClassificationExplanationBuilder.build(
            confirmed,
            language: .english
        )

        XCTAssertTrue(confirmedExplanation.isUserConfirmed)
        XCTAssertEqual(confirmedExplanation.status, "This activity")
        XCTAssertEqual(confirmedExplanation.confidenceText, "User confirmed")
        XCTAssertTrue(confirmedExplanation.summary.contains("priority"))
        XCTAssertEqual(confirmedExplanation.evidence, ["Confirmed by you"])
    }

    func testClassificationExplanationClampsInvalidConfidenceForPresentation() {
        let result = ActivityClassificationResult(
            purpose: .parking,
            confidence: 4.2,
            source: .heuristic,
            reasons: [.dwellPattern, .dwellPattern],
            classifierVersion: 2
        )

        let explanation = ActivityClassificationExplanationBuilder.build(
            result,
            language: .english
        )

        XCTAssertEqual(explanation.confidenceText, "100% confidence")
        XCTAssertEqual(explanation.evidence, ["Matched the typical stay duration"])
    }

    func testConflictingOverrideScopesKeepSessionOnlyAheadOfPlaceRule() throws {
        let parking = TeslaMateActivity(
            id: 50,
            type: "park",
            startDate: "2026-07-18T10:00:00Z",
            endDate: "2026-07-18T11:00:00Z"
        )
        let sessionOverride = ActivityLabelOverride(
            id: "session",
            carId: 1,
            sessionId: "1-50",
            placeKey: nil,
            scope: .sessionOnly,
            purpose: .pickupDropoff,
            customName: nil,
            icon: "figure.2.and.child.holdinghands",
            colorHex: "#FF9500",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newerPlaceOverride = ActivityLabelOverride(
            id: "place",
            carId: 1,
            sessionId: "1-50",
            placeKey: "parking:50",
            scope: .futureAtPlace,
            purpose: .shopping,
            customName: nil,
            icon: "cart.fill",
            colorHex: "#34C759",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking],
            sleepIntervals: [],
            geofences: [],
            labelOverrides: [newerPlaceOverride, sessionOverride]
        ).first)

        XCTAssertEqual(session.classification?.purpose, .pickupDropoff)
        XCTAssertEqual(session.classification?.source, .userSession)
    }

    func testPlaceRuleWindowUsesInjectedLocalTimeZone() throws {
        let parking = TeslaMateActivity(
            id: 20,
            type: "park",
            startDate: "2026-07-18T16:30:00Z",
            endDate: "2026-07-18T17:30:00Z"
        )
        let override = ActivityLabelOverride(
            id: "midnight-place",
            carId: 1,
            sessionId: nil,
            placeKey: "parking:20",
            scope: .futureAtPlace,
            purpose: .shopping,
            customName: nil,
            icon: "cart.fill",
            colorHex: "#34C759",
            startMinute: 0,
            endMinute: 60,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking],
            sleepIntervals: [],
            geofences: [],
            labelOverrides: [override],
            configuration: .init(calendar: calendar)
        ).first)

        XCTAssertEqual(session.classification?.purpose, .shopping)
        XCTAssertEqual(session.classification?.source, .userPlaceRule)
    }

    func testParkingPlaceRuleUsesParkingStartAsArrivalTimestamp() throws {
        let arrival = TeslaMateActivity(
            id: 30,
            type: "drive",
            startDate: "2026-07-18T08:00:00Z",
            endDate: "2026-07-18T09:00:00Z",
            endLatitude: SyntheticCoordinates.point().northing,
            endLongitude: SyntheticCoordinates.point().easting
        )
        let parking = TeslaMateActivity(
            id: 31,
            type: "park",
            startDate: "2026-07-18T10:30:00Z",
            endDate: "2026-07-18T11:30:00Z",
            endLatitude: SyntheticCoordinates.point().northing,
            endLongitude: SyntheticCoordinates.point().easting
        )
        let geofence = GeofenceRule(
            id: "arrival-place",
            name: "Arrival place",
            kind: .other,
            latitude: SyntheticCoordinates.point().northing,
            longitude: SyntheticCoordinates.point().easting,
            radiusMeters: 100
        )
        let override = ActivityLabelOverride(
            id: "parking-arrival-window",
            carId: 1,
            sessionId: nil,
            placeKey: "geofence:arrival-place",
            scope: .futureAtPlace,
            purpose: .shopping,
            customName: nil,
            icon: "cart.fill",
            colorHex: "#34C759",
            startMinute: 10 * 60,
            endMinute: 11 * 60,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [arrival, parking],
            sleepIntervals: [],
            geofences: [geofence],
            labelOverrides: [override],
            configuration: .init(calendar: calendar)
        ).first)

        // TeslaMate activity IDs are source IDs; the approved stable session ID remains carId-sourceID.
        XCTAssertEqual(session.id, "1-31")
        XCTAssertEqual(session.eventReferences.map(\.sourceID), [30, 31])
        XCTAssertEqual(session.classification?.purpose, .shopping)
        XCTAssertEqual(session.classification?.source, .userPlaceRule)
    }

    func testFallbackDrivePlaceRuleUsesDriveEndAsArrivalTimestamp() throws {
        let drive = TeslaMateActivity(
            id: 40,
            type: "drive",
            startDate: "2026-07-18T08:00:00Z",
            endDate: "2026-07-18T10:30:00Z",
            endLatitude: SyntheticCoordinates.point().northing,
            endLongitude: SyntheticCoordinates.point().easting
        )
        let geofence = GeofenceRule(
            id: "drive-arrival",
            name: "Drive arrival",
            kind: .other,
            latitude: SyntheticCoordinates.point().northing,
            longitude: SyntheticCoordinates.point().easting,
            radiusMeters: 100
        )
        let override = ActivityLabelOverride(
            id: "drive-arrival-window",
            carId: 1,
            sessionId: nil,
            placeKey: "geofence:drive-arrival",
            scope: .futureAtPlace,
            purpose: .pickupDropoff,
            customName: nil,
            icon: "figure.2.and.child.holdinghands",
            colorHex: "#FF9500",
            startMinute: 10 * 60,
            endMinute: 11 * 60,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [drive],
            sleepIntervals: [],
            geofences: [geofence],
            labelOverrides: [override],
            configuration: .init(calendar: calendar)
        ).first)

        XCTAssertEqual(session.id, "1-40")
        XCTAssertEqual(session.eventReferences.map(\.sourceID), [40])
        XCTAssertEqual(session.classification?.purpose, .pickupDropoff)
        XCTAssertEqual(session.classification?.source, .userPlaceRule)
    }

    func testReconstructionAppliesMatchingSessionOverrideWithoutChangingSources() throws {
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
            icon: "dumbbell.fill",
            colorHex: "#123456",
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

        let classification = try XCTUnwrap(session?.classification)
        let restored = try JSONDecoder().decode(
            ActivityClassificationResult.self,
            from: JSONEncoder().encode(classification)
        )
        let legacy = try JSONDecoder().decode(
            ActivityClassificationResult.self,
            from: Data(
                """
                {
                  "purpose": "custom",
                  "confidence": 1,
                  "source": "userSession",
                  "reasons": ["confirmedOverride"],
                  "classifierVersion": 1
                }
                """.utf8
            )
        )

        XCTAssertEqual(classification.purpose, .custom)
        XCTAssertEqual(classification.source, .userSession)
        XCTAssertEqual(classification.title(language: .english), "Gym")
        XCTAssertEqual(classification.systemImage, "dumbbell.fill")
        XCTAssertEqual(classification.colorHex, "#123456")
        XCTAssertEqual(restored, classification)
        XCTAssertNil(legacy.customPresentation)
        XCTAssertEqual(legacy.title(language: .english), "Custom activity")
        XCTAssertEqual(legacy.systemImage, "tag.fill")
        XCTAssertNil(legacy.colorHex)
        XCTAssertEqual(session?.id, "1-1")
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
        isConfirmedCommute: Bool = false,
        arrivalMinute: Int? = nil,
        isWeekday: Bool? = nil,
        dwellMinutes: Int? = nil
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
            isConfirmedCommute: isConfirmedCommute,
            arrivalMinute: arrivalMinute,
            isWeekday: isWeekday,
            dwellMinutes: dwellMinutes
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
    static func fixture(
        purpose: SmartActivityPurpose,
        scope: ActivityLabelScope = .sessionOnly
    ) -> ActivityLabelOverride {
        ActivityLabelOverride(
            id: "override-\(purpose.rawValue)",
            carId: 1,
            sessionId: "session",
            placeKey: "place",
            scope: scope,
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
