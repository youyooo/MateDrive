import Foundation

public struct TripMembership: Equatable, Sendable {
    public let snapshot: SavedTripSnapshot
    public let trip: DetectedTrip
}

public protocol TripMembershipManaging: Sendable {
    func membership(carId: Int, leg: TripLegReference) async throws -> TripMembership?
    func remove(carId: Int, leg: TripLegReference) async throws
}

public struct TripMembershipService: TripMembershipManaging {
    private let dataProvider: any TripDataProviding
    private let tripStore: any TripPersisting

    public init(dataProvider: any TripDataProviding, tripStore: any TripPersisting) {
        self.dataProvider = dataProvider
        self.tripStore = tripStore
    }

    public func membership(carId: Int, leg: TripLegReference) async throws -> TripMembership? {
        let source = try await sourceData(carId: carId)
        let snapshots = try await tripStore.savedTrips(carId: carId)
        guard
            let snapshot = snapshots.first(where: { $0.legs.contains(leg) }),
            let trip = await TripsViewModel.buildTrips(from: [snapshot], source: source).first
        else { return nil }
        return TripMembership(snapshot: snapshot, trip: trip)
    }

    public func remove(carId: Int, leg: TripLegReference) async throws {
        let source = try await sourceData(carId: carId)
        let snapshots = try await tripStore.savedTrips(carId: carId)
        guard let snapshot = snapshots.first(where: { $0.legs.contains(leg) }) else { return }
        let remaining = snapshot.legs.filter { $0 != leg }
        guard remaining.contains(where: { if case .drive = $0 { return true }; return false }) else {
            try await tripStore.deleteTrip(tripId: snapshot.tripId)
            return
        }
        guard let trip = await TripsViewModel.buildTrips(
            from: [SavedTripSnapshot(tripId: snapshot.tripId, carId: carId, name: snapshot.name, startDate: snapshot.startDate, endDate: snapshot.endDate, legs: remaining)],
            source: source
        ).first else { return }
        let fingerprint = TripFingerprint.fingerprint(driveIds: snapshot.legs.compactMap {
            if case let .drive(id) = $0 { return id }
            return nil
        })
        try await tripStore.updateTrip(
            tripId: snapshot.tripId,
            name: snapshot.name,
            startDate: trip.startDate,
            endDate: trip.endDate,
            legs: remaining,
            consumedFingerprints: snapshot.consumedFingerprints.union([fingerprint])
        )
    }

    private func sourceData(carId: Int) async throws -> TripSourceData {
        switch await dataProvider.sourceData(carId: carId) {
        case let .success(source): return source
        case let .failure(error): throw error
        }
    }
}
