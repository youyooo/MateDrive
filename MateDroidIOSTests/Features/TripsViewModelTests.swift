import XCTest
@testable import MateDroidIOS

@MainActor
final class TripsViewModelTests: XCTestCase {
    func testTripsViewModelAutoPersistsDetectedTripsAndBuildsSummary() async throws {
        let store = InMemoryTripStore()
        let viewModel = TripsViewModel(
            dataProvider: FakeTripDataProvider(source: .roadTrip),
            tripStore: store,
            settingsStore: StaticTripSettingsStore()
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.trips.count, 1)
        XCTAssertEqual(viewModel.state.totalDistance, 330)
        XCTAssertEqual(viewModel.state.totalDrivingMin, 210)
        XCTAssertEqual(viewModel.state.totalEnergyCharged, 45)
        XCTAssertEqual(viewModel.state.totalChargeCost, 18)
        XCTAssertEqual(viewModel.state.pricedChargeCount, 1)
        XCTAssertEqual(viewModel.state.totalChargeCount, 1)
        XCTAssertTrue(viewModel.state.chargeCostIsComplete)
        let saved = await store.savedTrips
        XCTAssertEqual(saved.first?.legs, [.drive(10), .charge(20), .drive(11)])
        XCTAssertEqual(saved.first?.consumedFingerprints.count, 1)
    }

    func testTripsViewModelUsesSelectedCurrencyForCostPresentation() async {
        let viewModel = TripsViewModel(
            dataProvider: FakeTripDataProvider(source: .roadTrip),
            tripStore: InMemoryTripStore(),
            settingsStore: StaticTripSettingsStore(settings: AppSettings(currencyCode: "CNY"))
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.currencySymbol, "¥")
    }

    func testTripsSummaryDoesNotTreatMissingChargeCostAsZero() async {
        let source = TripSourceData(
            drives: TripSourceData.roadTrip.drives,
            charges: [
                TripCharge(
                    id: 20,
                    startDate: "2026-01-01T10:05:00Z",
                    endDate: "2026-01-01T10:35:00Z",
                    energyAdded: 45,
                    cost: nil,
                    address: "Supercharger Lyon"
                )
            ],
            dcChargeIds: [20],
            units: .metric
        )
        let viewModel = TripsViewModel(
            dataProvider: FakeTripDataProvider(source: source),
            tripStore: InMemoryTripStore(),
            settingsStore: StaticTripSettingsStore()
        )

        await viewModel.load(carId: 1)

        XCTAssertNil(viewModel.state.totalChargeCost)
        XCTAssertEqual(viewModel.state.pricedChargeCount, 0)
        XCTAssertEqual(viewModel.state.totalChargeCount, 1)
        XCTAssertFalse(viewModel.state.chargeCostIsComplete)
    }

    func testCreateTripPersistsOrderedLegsAndConsumedFingerprint() async throws {
        let store = InMemoryTripStore()
        let viewModel = CreateTripViewModel(tripStore: store)

        await viewModel.createTrip(
            carId: 1,
            name: "Summer Trip",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: ["10-20-11"]
        )

        let saved = await store.savedTrips
        XCTAssertEqual(saved.first?.name, "Summer Trip")
        XCTAssertEqual(saved.first?.legs, [.drive(10), .charge(20), .drive(11)])
        XCTAssertEqual(saved.first?.consumedFingerprints, ["10-20-11"])
    }

    func testCreateTripLoadPreservesServerUnitsForDynamicPresentation() async {
        let store = InMemoryTripStore()
        let viewModel = CreateTripViewModel(
            tripStore: store,
            dataProvider: FakeTripDataProvider(source: .roadTrip)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.units, .metric)
        XCTAssertEqual(viewModel.state.availableDrives.first?.distance, 180)
    }
}

actor InMemoryTripStore: TripPersisting {
    private(set) var savedTrips: [SavedTripSnapshot] = []

    func saveTrip(
        carId: Int,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws -> SavedTripSnapshot {
        let snapshot = SavedTripSnapshot(
            tripId: UUID().uuidString,
            carId: carId,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate,
            legs: legs,
            consumedFingerprints: consumedFingerprints
        )
        savedTrips.append(snapshot)
        return snapshot
    }

    func savedTrips(carId: Int) async throws -> [SavedTripSnapshot] {
        savedTrips.filter { $0.carId == carId }
    }

    func renameTrip(tripId: String, name: String?) async throws {
        savedTrips = savedTrips.map { trip in
            guard trip.tripId == tripId else { return trip }
            return SavedTripSnapshot(
                tripId: trip.tripId,
                carId: trip.carId,
                name: name,
                startDate: trip.startDate,
                endDate: trip.endDate,
                legs: trip.legs,
                consumedFingerprints: trip.consumedFingerprints
            )
        }
    }

    func deleteTrip(tripId: String) async throws {
        savedTrips.removeAll { $0.tripId == tripId }
    }

    func replaceLegs(tripId: String, legs: [TripLegReference], consumedFingerprints: Set<String>) async throws {
        savedTrips = savedTrips.map { trip in
            guard trip.tripId == tripId else { return trip }
            return SavedTripSnapshot(
                tripId: trip.tripId,
                carId: trip.carId,
                name: trip.name,
                startDate: trip.startDate,
                endDate: trip.endDate,
                legs: legs,
                consumedFingerprints: consumedFingerprints
            )
        }
    }

    func updateTrip(
        tripId: String,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws {
        guard let index = savedTrips.firstIndex(where: { $0.tripId == tripId }) else { return }
        let previous = savedTrips[index]
        savedTrips[index] = SavedTripSnapshot(
            tripId: tripId,
            carId: previous.carId,
            name: name,
            startDate: startDate,
            endDate: endDate,
            legs: legs,
            consumedFingerprints: consumedFingerprints
        )
    }

    func mergeTrips(keptTripId: String, consumedTripId: String, merged: SavedTripSnapshot) async throws {
        savedTrips.removeAll { $0.tripId == keptTripId || $0.tripId == consumedTripId }
        savedTrips.append(merged)
    }
}

struct FakeTripDataProvider: TripDataProviding {
    let source: TripSourceData
    var routes: [SavedTripRouteSegment] = []

    func sourceData(carId _: Int) async -> APIResult<TripSourceData> {
        .success(source)
    }

    func routeSegments(carId _: Int, driveIds: [Int]) async -> [SavedTripRouteSegment] {
        driveIds.compactMap { driveId in routes.first { $0.driveId == driveId } }
    }
}

struct StaticTripSettingsStore: SettingsStoring {
    var settings = AppSettings(showShortDrivesCharges: true)

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {}
}

extension TripSourceData {
    static let roadTrip = TripSourceData(
        drives: [
            TripDrive(
                id: 10,
                startDate: "2026-01-01T08:00:00Z",
                endDate: "2026-01-01T10:00:00Z",
                distance: 180,
                durationMin: 120,
                energyConsumed: 32,
                speedMax: 120,
                startAddress: "Paris, France",
                endAddress: "Lyon, France"
            ),
            TripDrive(
                id: 11,
                startDate: "2026-01-01T10:40:00Z",
                endDate: "2026-01-01T12:10:00Z",
                distance: 150,
                durationMin: 90,
                energyConsumed: 27,
                speedMax: 118,
                startAddress: "Lyon, France",
                endAddress: "Geneva, Switzerland"
            )
        ],
        charges: [
            TripCharge(
                id: 20,
                startDate: "2026-01-01T10:05:00Z",
                endDate: "2026-01-01T10:35:00Z",
                energyAdded: 45,
                cost: 18,
                address: "Supercharger Lyon"
            )
        ],
        dcChargeIds: [20],
        units: .metric
    )
}
