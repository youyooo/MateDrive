import XCTest
@testable import MateDroidIOS

final class ActivitySessionReconstructorTests: XCTestCase {
    func testGroupsArrivalChargeAndPromptDepartureAsOneSession() throws {
        let events = ActivityReconstructionFixtures.publicChargingStop()
        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: events,
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.chargingFence]
        )

        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.eventReferences.map(\.kind), [.drive, .park, .charge, .drive])
        XCTAssertEqual(session.provisionalKind, .replenishment)
        XCTAssertFalse(session.isOpen)
    }

    func testHomeStayAllowsScheduledChargeAfterShortStopWindow() throws {
        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: ActivityReconstructionFixtures.homeOvernightCharge(arrivalHour: 18, chargeHour: 23),
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.homeFence]
        )

        XCTAssertEqual(sessions.first?.provisionalKind, .homeCharging)
        XCTAssertEqual(sessions.first?.eventReferences.map(\.kind), [.drive, .park, .charge, .drive])
    }

    func testLeavesUnfinishedParkingAsOneOpenSession() throws {
        let parking = TeslaMateActivity(
            id: 100,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )

        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking],
            sleepIntervals: [],
            geofences: []
        )

        let session = try XCTUnwrap(sessions.first)
        XCTAssertTrue(session.isOpen)
        XCTAssertNil(session.endDate)
        XCTAssertEqual(session.eventReferences.map(\.kind), [.park])
    }

    func testLaterDepartureChangesFingerprintWithoutChangingStableID() throws {
        let openParking = TeslaMateActivity(
            id: 101,
            type: "park",
            startDate: "2026-07-18T10:30:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let closedParking = TeslaMateActivity(
            id: 101,
            type: "park",
            startDate: "2026-07-18T10:30:00+08:00",
            endDate: "2026-07-18T11:30:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let arrival = TeslaMateActivity(
            id: 102,
            type: "drive",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T10:30:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let departure = TeslaMateActivity(
            id: 103,
            type: "drive",
            startDate: "2026-07-18T11:35:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        )

        let beforeDeparture = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [arrival, openParking],
            sleepIntervals: [],
            geofences: []
        ).first)
        let afterDeparture = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [arrival, closedParking, departure],
            sleepIntervals: [],
            geofences: []
        ).first)

        XCTAssertTrue(beforeDeparture.isOpen)
        XCTAssertFalse(afterDeparture.isOpen)
        XCTAssertEqual(afterDeparture.id, beforeDeparture.id)
        XCTAssertNotEqual(afterDeparture.sourceFingerprint, beforeDeparture.sourceFingerprint)
        XCTAssertEqual(afterDeparture.eventReferences.map(\.kind), [.drive, .park, .drive])
    }

    func testIgnoresDuplicateSourceEvents() throws {
        let events = ActivityReconstructionFixtures.publicChargingStop()
        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: events + [events[2]],
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.chargingFence]
        )

        XCTAssertEqual(sessions.first?.eventReferences.map(\.kind), [.drive, .park, .charge, .drive])
    }

    func testDoesNotMergeDepartureAtDifferentCoordinates() throws {
        var events = ActivityReconstructionFixtures.publicChargingStop()
        events[3] = TeslaMateActivity(
            id: 13,
            type: "drive",
            startDate: "2026-07-18T11:35:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            startLatitude: 31.2504,
            startLongitude: 121.4937
        )

        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: events,
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.chargingFence]
        )

        XCTAssertEqual(sessions.first { $0.id == "1-11" }?.eventReferences.map(\.kind), [.drive, .park, .charge])
    }

    func testDoesNotAttachChargeAfterNonHomeSourceGap() throws {
        let events = [
            TeslaMateActivity(
                id: 200,
                type: "park",
                startDate: "2026-07-18T10:00:00+08:00",
                endDate: "2026-07-18T14:00:00+08:00",
                endLatitude: 31.2304,
                endLongitude: 121.4737
            ),
            TeslaMateActivity(
                id: 201,
                type: "charge",
                startDate: "2026-07-18T12:30:00+08:00",
                endDate: "2026-07-18T13:00:00+08:00",
                startLatitude: 31.2304,
                startLongitude: 121.4737
            )
        ]

        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: events,
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.chargingFence]
        )

        XCTAssertEqual(sessions.first?.eventReferences.map(\.kind), [.park])
    }

    func testCreatesPartialFallbackForDriveWithoutParkingSource() throws {
        let drive = TeslaMateActivity(
            id: 300,
            type: "drive",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T10:25:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [drive],
            sleepIntervals: [],
            geofences: [ActivityReconstructionFixtures.chargingFence]
        ).first)

        XCTAssertEqual(session.id, "1-300")
        XCTAssertEqual(session.eventReferences.map(\.sourceID), [300])
        XCTAssertNil(session.parkingMetrics)
        XCTAssertNil(session.chargeCost)
        XCTAssertEqual(session.quality, .partial)
    }

    func testDepartureSearchSkipsMismatchedDriveWithinGrace() throws {
        let parking = TeslaMateActivity(
            id: 400,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T11:00:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let mismatchedDeparture = TeslaMateActivity(
            id: 401,
            type: "drive",
            startDate: "2026-07-18T11:05:00+08:00",
            endDate: "2026-07-18T11:20:00+08:00",
            startLatitude: 31.2504,
            startLongitude: 121.4937
        )
        let matchingDeparture = TeslaMateActivity(
            id: 402,
            type: "drive",
            startDate: "2026-07-18T11:10:00+08:00",
            endDate: "2026-07-18T11:30:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        )

        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking, mismatchedDeparture, matchingDeparture],
            sleepIntervals: [],
            geofences: []
        )

        XCTAssertEqual(sessions.first { $0.id == "1-400" }?.eventReferences.map(\.sourceID), [400, 402])
        XCTAssertEqual(sessions.first { $0.id == "1-401" }?.eventReferences.map(\.sourceID), [401])
    }

    func testDoesNotAttachDriveToMoreThanOneParkingSession() throws {
        let firstParking = TeslaMateActivity(
            id: 500,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T10:30:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let connectingDrive = TeslaMateActivity(
            id: 501,
            type: "drive",
            startDate: "2026-07-18T10:35:00+08:00",
            endDate: "2026-07-18T11:00:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let secondParking = TeslaMateActivity(
            id: 502,
            type: "park",
            startDate: "2026-07-18T11:00:00+08:00",
            endDate: "2026-07-18T11:30:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )

        let sessions = ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [firstParking, connectingDrive, secondParking],
            sleepIntervals: [],
            geofences: []
        )

        XCTAssertEqual(sessions.flatMap(\.eventReferences).filter { $0.sourceID == 501 }.count, 1)
        XCTAssertEqual(sessions.first { $0.id == "1-502" }?.eventReferences.map(\.sourceID), [502])
    }

    func testOnlyAttachesClosedChargeFullyInsideParkingInterval() throws {
        let parking = TeslaMateActivity(
            id: 600,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T11:00:00+08:00",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        )
        let completeCharge = TeslaMateActivity(
            id: 601,
            type: "charge",
            startDate: "2026-07-18T10:10:00+08:00",
            endDate: "2026-07-18T10:50:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        )
        let openCharge = TeslaMateActivity(
            id: 602,
            type: "charge",
            startDate: "2026-07-18T10:20:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        )
        let overlappingCharge = TeslaMateActivity(
            id: 603,
            type: "charge",
            startDate: "2026-07-18T10:30:00+08:00",
            endDate: "2026-07-18T11:10:00+08:00",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        )

        let session = try XCTUnwrap(ActivitySessionReconstructor.reconstruct(
            carId: 1,
            events: [parking, completeCharge, openCharge, overlappingCharge],
            sleepIntervals: [],
            geofences: []
        ).first { $0.id == "1-600" })

        XCTAssertEqual(session.eventReferences.map(\.sourceID), [600, 601])
    }
}

private enum ActivityReconstructionFixtures {
    static let chargingFence = GeofenceRule(
        id: "charging-fence",
        name: "Public Charger",
        kind: .charging,
        latitude: 31.2304,
        longitude: 121.4737,
        radiusMeters: 100
    )

    static let homeFence = GeofenceRule(
        id: "home-fence",
        name: "Home",
        kind: .home,
        latitude: 31.2304,
        longitude: 121.4737,
        radiusMeters: 100
    )

    static func publicChargingStop() -> [TeslaMateActivity] {
        [
            TeslaMateActivity(
                id: 10,
                type: "drive",
                startDate: "2026-07-18T10:00:00+08:00",
                endDate: "2026-07-18T10:30:00+08:00",
                endLatitude: 31.2304,
                endLongitude: 121.4737
            ),
            TeslaMateActivity(
                id: 11,
                type: "park",
                startDate: "2026-07-18T10:30:00+08:00",
                endDate: "2026-07-18T11:30:00+08:00",
                endLatitude: 31.2304,
                endLongitude: 121.4737,
                soc: 50,
                socDiff: 20,
                endRangeKm: 320
            ),
            TeslaMateActivity(
                id: 12,
                type: "charge",
                startDate: "2026-07-18T10:35:00+08:00",
                endDate: "2026-07-18T11:25:00+08:00",
                startLatitude: 31.2304,
                startLongitude: 121.4737,
                kwh: 14,
                socDiff: 22
            ),
            TeslaMateActivity(
                id: 13,
                type: "drive",
                startDate: "2026-07-18T11:35:00+08:00",
                endDate: "2026-07-18T12:00:00+08:00",
                startLatitude: 31.2304,
                startLongitude: 121.4737
            )
        ]
    }

    static func homeOvernightCharge(arrivalHour: Int, chargeHour: Int) -> [TeslaMateActivity] {
        let arrival = String(format: "2026-07-18T%02d:00:00+08:00", arrivalHour)
        let charge = String(format: "2026-07-18T%02d:00:00+08:00", chargeHour)
        return [
            TeslaMateActivity(
                id: 30,
                type: "drive",
                startDate: "2026-07-18T17:30:00+08:00",
                endDate: arrival,
                endLatitude: 31.2304,
                endLongitude: 121.4737
            ),
            TeslaMateActivity(
                id: 31,
                type: "park",
                startDate: arrival,
                endDate: "2026-07-19T07:00:00+08:00",
                endLatitude: 31.2304,
                endLongitude: 121.4737
            ),
            TeslaMateActivity(
                id: 32,
                type: "charge",
                startDate: charge,
                endDate: "2026-07-19T01:00:00+08:00",
                startLatitude: 31.2304,
                startLongitude: 121.4737,
                kwh: 18,
                socDiff: 25
            ),
            TeslaMateActivity(
                id: 33,
                type: "drive",
                startDate: "2026-07-19T07:05:00+08:00",
                endDate: "2026-07-19T07:30:00+08:00",
                startLatitude: 31.2304,
                startLongitude: 121.4737
            )
        ]
    }
}
