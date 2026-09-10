import XCTest
@testable import MateDriveApp

final class AdjacentDriveMergerTests: XCTestCase {
    func testMergesNearbyDrivesAcrossShortParkingAndPreservesOriginalSegments() throws {
        let first = drive(
            id: 1,
            start: "2026-07-15T09:30:00Z",
            end: "2026-07-15T10:00:00Z",
            startAddress: "Home",
            endAddress: "Coffee",
            startCoordinate: (28.10, 112.80),
            endCoordinate: (28.2000, 112.9000),
            distance: 10,
            duration: 30,
            energy: 2
        )
        let parking = TeslaMateActivity(
            id: 9,
            type: "park",
            startDate: "2026-07-15T10:00:00Z",
            endDate: "2026-07-15T10:12:00Z",
            durationMin: 12,
            startAddress: "Coffee"
        )
        let second = drive(
            id: 2,
            start: "2026-07-15T10:12:00Z",
            end: "2026-07-15T10:32:00Z",
            startAddress: "Coffee Shop",
            endAddress: "Office",
            startCoordinate: (28.2004, 112.9003),
            endCoordinate: (28.30, 113.00),
            distance: 5,
            duration: 20,
            energy: 1
        )

        let entries = AdjacentDriveMerger.entries(
            from: [second, parking, first],
            configuration: AdjacentDriveMergeConfiguration(maximumGapMinutes: 30)
        )

        XCTAssertEqual(entries.count, 1)
        guard case let .mergedDrive(group) = try XCTUnwrap(entries.first) else {
            return XCTFail("Expected merged drive group")
        }
        XCTAssertEqual(group.drives.map(\.id), [1, 2])
        XCTAssertEqual(group.intermediateParking.map(\.id), [9])
        XCTAssertEqual(group.connections.count, 1)
        XCTAssertEqual(group.connections.first?.locationEvidence, .coordinates)
        XCTAssertEqual(group.connections.first?.gapMinutes, 12)
        XCTAssertEqual(group.distance.value, 15)
        XCTAssertTrue(group.distance.isComplete)
        XCTAssertEqual(group.drivingEnergy.value, 3)
        XCTAssertEqual(group.paginationAnchor.id, 1)
    }

    func testChargeBetweenDrivesAlwaysPreventsMerge() {
        let first = addressDrive(id: 1, start: "2026-07-15T09:00:00Z", end: "2026-07-15T10:00:00Z")
        let charge = TeslaMateActivity(id: 7, type: "charge", startDate: "2026-07-15T10:05:00Z", endDate: "2026-07-15T10:20:00Z")
        let second = addressDrive(id: 2, start: "2026-07-15T10:25:00Z", end: "2026-07-15T11:00:00Z")

        let entries = AdjacentDriveMerger.entries(from: [second, charge, first], configuration: .init())

        XCTAssertEqual(entries.count, 3)
        XCTAssertFalse(entries.contains { if case .mergedDrive = $0 { return true }; return false })
    }

    func testCoordinateDistanceTakesPrecedenceOverMatchingAddress() {
        let first = drive(
            id: 1,
            start: "2026-07-15T09:00:00Z",
            end: "2026-07-15T10:00:00Z",
            startAddress: "A",
            endAddress: "Same Place",
            startCoordinate: (28, 112),
            endCoordinate: (28, 112),
            distance: 1,
            duration: 60,
            energy: nil
        )
        let second = drive(
            id: 2,
            start: "2026-07-15T10:10:00Z",
            end: "2026-07-15T11:00:00Z",
            startAddress: "Same Place",
            endAddress: "B",
            startCoordinate: (29, 113),
            endCoordinate: (29.1, 113.1),
            distance: 1,
            duration: 50,
            energy: nil
        )

        let entries = AdjacentDriveMerger.entries(from: [second, first], configuration: .init())

        XCTAssertEqual(entries.count, 2)
    }

    func testUsesNormalizedAddressOnlyWhenCoordinatesAreUnavailable() throws {
        let first = addressDrive(id: 1, start: "2026-07-15T09:00:00Z", end: "2026-07-15T10:00:00Z", endAddress: "  Café Central ")
        let second = addressDrive(id: 2, start: "2026-07-15T10:10:00Z", end: "2026-07-15T11:00:00Z", startAddress: "cafe   central")

        let entries = AdjacentDriveMerger.entries(from: [second, first], configuration: .init())

        guard case let .mergedDrive(group) = try XCTUnwrap(entries.first) else {
            return XCTFail("Expected address-backed merge")
        }
        XCTAssertEqual(group.connections.first?.locationEvidence, .address)
        XCTAssertNil(group.connections.first?.distanceMeters)
    }

    func testDoesNotMergeAcrossDayBoundaryOrWithoutCompleteTimes() {
        let first = addressDrive(id: 1, start: "2026-07-15T23:30:00Z", end: "2026-07-15T23:55:00Z")
        let nextDay = addressDrive(id: 2, start: "2026-07-16T00:05:00Z", end: "2026-07-16T00:30:00Z")
        let missingEnd = TeslaMateActivity(id: 3, type: "drive", startDate: "2026-07-16T01:00:00Z", endAddress: "Stop")
        let afterMissing = addressDrive(id: 4, start: "2026-07-16T01:10:00Z", end: "2026-07-16T01:30:00Z", startAddress: "Stop")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let entries = AdjacentDriveMerger.entries(
            from: [afterMissing, missingEnd, nextDay, first],
            configuration: .init(),
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 4)
    }

    func testThresholdAndDisabledConfigurationPreventMerge() {
        let first = addressDrive(id: 1, start: "2026-07-15T09:00:00Z", end: "2026-07-15T10:00:00Z")
        let second = addressDrive(id: 2, start: "2026-07-15T10:31:00Z", end: "2026-07-15T11:00:00Z")

        XCTAssertEqual(
            AdjacentDriveMerger.entries(from: [second, first], configuration: .init(maximumGapMinutes: 30)).count,
            2
        )
        XCTAssertEqual(
            AdjacentDriveMerger.entries(from: [second, first], configuration: .init(isEnabled: false, maximumGapMinutes: 60)).count,
            2
        )
    }

    func testAggregateMeasurementDoesNotTurnMissingValuesIntoZero() throws {
        let first = addressDrive(id: 1, start: "2026-07-15T09:00:00Z", end: "2026-07-15T10:00:00Z", distance: 8)
        let second = addressDrive(id: 2, start: "2026-07-15T10:10:00Z", end: "2026-07-15T11:00:00Z", distance: nil)

        let entries = AdjacentDriveMerger.entries(from: [second, first], configuration: .init())
        guard case let .mergedDrive(group) = try XCTUnwrap(entries.first) else {
            return XCTFail("Expected merged drive group")
        }
        XCTAssertEqual(group.distance.value, 8)
        XCTAssertEqual(group.distance.knownCount, 1)
        XCTAssertEqual(group.distance.totalCount, 2)
        XCTAssertFalse(group.distance.isComplete)
    }

    private func addressDrive(
        id: Int,
        start: String,
        end: String,
        startAddress: String = "Stop",
        endAddress: String = "Stop",
        distance: Double? = 1
    ) -> TeslaMateActivity {
        drive(
            id: id,
            start: start,
            end: end,
            startAddress: startAddress,
            endAddress: endAddress,
            startCoordinate: nil,
            endCoordinate: nil,
            distance: distance,
            duration: 10,
            energy: nil
        )
    }

    private func drive(
        id: Int,
        start: String,
        end: String,
        startAddress: String,
        endAddress: String,
        startCoordinate: (Double, Double)?,
        endCoordinate: (Double, Double)?,
        distance: Double?,
        duration: Double?,
        energy: Double?
    ) -> TeslaMateActivity {
        TeslaMateActivity(
            id: id,
            type: "drive",
            startDate: start,
            endDate: end,
            durationMin: duration,
            startAddress: startAddress,
            endAddress: endAddress,
            startLatitude: startCoordinate?.0,
            startLongitude: startCoordinate?.1,
            endLatitude: endCoordinate?.0,
            endLongitude: endCoordinate?.1,
            kwhUsed: energy,
            distanceKm: distance
        )
    }
}
