import XCTest
@testable import MateDriveApp

final class TripMembershipServiceTests: XCTestCase {
    func testFindsMembershipAndRemovesCharge() async throws {
        let store = InMemoryTripStore()
        let saved = try await saveRoadTrip(in: store)
        let service = TripMembershipService(dataProvider: FakeTripDataProvider(source: .roadTrip), tripStore: store)

        let membership = try await service.membership(carId: 1, leg: .charge(20))
        XCTAssertEqual(membership?.snapshot.tripId, saved.tripId)

        try await service.remove(carId: 1, leg: .charge(20))
        let stored = try await snapshots(in: store)
        let updated = try XCTUnwrap(stored.first)
        XCTAssertEqual(updated.legs, [.drive(10), .drive(11)])
        XCTAssertEqual(updated.startDate, "2026-01-01T08:00:00Z")
        XCTAssertEqual(updated.endDate, "2026-01-01T12:10:00Z")
    }

    func testRemovingFirstDriveRecalculatesRange() async throws {
        let store = InMemoryTripStore()
        _ = try await saveRoadTrip(in: store)
        let service = TripMembershipService(dataProvider: FakeTripDataProvider(source: .roadTrip), tripStore: store)

        try await service.remove(carId: 1, leg: .drive(10))

        let stored = try await snapshots(in: store)
        let updated = try XCTUnwrap(stored.first)
        XCTAssertEqual(updated.legs, [.charge(20), .drive(11)])
        XCTAssertEqual(updated.startDate, "2026-01-01T10:40:00Z")
        XCTAssertEqual(updated.endDate, "2026-01-01T12:10:00Z")
    }

    func testRemovingOnlyDriveDeletesTrip() async throws {
        let store = InMemoryTripStore()
        _ = try await store.saveTrip(carId: 1, name: nil, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T10:00:00Z", legs: [.drive(10)], consumedFingerprints: [])
        let service = TripMembershipService(dataProvider: FakeTripDataProvider(source: .roadTrip), tripStore: store)

        try await service.remove(carId: 1, leg: .drive(10))

        let stored = try await snapshots(in: store)
        XCTAssertTrue(stored.isEmpty)
    }

    private func saveRoadTrip(in store: InMemoryTripStore) async throws -> SavedTripSnapshot {
        try await store.saveTrip(
            carId: 1,
            name: "Summer Trip",
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: []
        )
    }

    private func snapshots(in store: InMemoryTripStore) async throws -> [SavedTripSnapshot] {
        try await store.savedTrips(carId: 1)
    }
}
