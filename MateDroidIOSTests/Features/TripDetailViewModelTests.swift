import XCTest
@testable import MateDroidIOS

@MainActor
final class TripDetailViewModelTests: XCTestCase {
    func testTripDetailBuildsTimelineWithParkingAndDcChargeSegments() async throws {
        let store = InMemoryTripStore()
        _ = try await store.saveTrip(
            carId: 1,
            name: "Summer Trip",
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: []
        )
        let viewModel = TripDetailViewModel(
            dataProvider: FakeTripDataProvider(source: .roadTrip),
            tripStore: store,
            settingsStore: StaticTripSettingsStore()
        )

        await viewModel.load(carId: 1, tripStartDate: "2026-01-01T08:00:00Z")

        XCTAssertEqual(viewModel.state.trip?.displayName, "Summer Trip")
        XCTAssertEqual(viewModel.state.timeline.map(\.kind), [.drive, .parking, .dcCharge, .parking, .drive])
        XCTAssertEqual(viewModel.state.timeline.filter { $0.kind == .parking }.map(\.durationMin), [5, 5])
        XCTAssertEqual(viewModel.state.units, .metric)
        XCTAssertEqual(viewModel.state.editableLegs.first?.distanceKm, 180)
        XCTAssertNil(viewModel.state.editableLegs.first?.energyKWh)
        XCTAssertEqual(viewModel.state.editableLegs.first { $0.reference == .charge(20) }?.energyKWh, 45)
        XCTAssertEqual(viewModel.state.countrySummary?.classifiedRecordCount, 2)
        XCTAssertEqual(viewModel.state.countrySummary?.totalRecordCount, 3)
        XCTAssertEqual(viewModel.state.countrySummary?.unclassifiedRecordCount, 1)
        XCTAssertEqual(viewModel.state.countrySummary?.countries.map(\.countryCode), ["FR", "CH"])
        let france = viewModel.state.countrySummary?.countries.first { $0.countryCode == "FR" }
        XCTAssertEqual(france?.driveCount, 1)
        XCTAssertEqual(france?.chargeCount, 0)
        XCTAssertEqual(france?.distanceKm, 180)
        XCTAssertEqual(france?.chargedEnergyKWh, 0)
    }

    func testTripCountrySummaryReportsUnclassifiedRecordsWithoutGuessingDistricts() throws {
        let trip = try XCTUnwrap(TripAggregator.buildTrip(
            drives: [
                TripDrive(id: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T09:00:00Z", distance: 20, durationMin: 60, endAddress: "岳麓区, 长沙市"),
                TripDrive(id: 2, startDate: "2026-01-01T10:00:00Z", endDate: "2026-01-01T11:00:00Z", distance: 30, durationMin: 60, endAddress: "长沙市, 中国")
            ],
            charges: [TripCharge(id: 3, startDate: "2026-01-01T09:00:00Z", endDate: "2026-01-01T09:30:00Z", energyAdded: 10, address: nil)]
        ))

        let summary = TripCountrySummary.build(trip: trip)

        XCTAssertEqual(summary.countries.map(\.countryCode), ["CN"])
        XCTAssertEqual(summary.classifiedRecordCount, 1)
        XCTAssertEqual(summary.totalRecordCount, 3)
        XCTAssertEqual(summary.unclassifiedRecordCount, 2)
        XCTAssertEqual(summary.countries.first?.distanceKm, 30)
    }

    func testTripDetailLoadsOnlySavedDriveRoutesAndKeepsSegmentBoundaries() async throws {
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: []
        )
        let firstRouteStart = SyntheticCoordinates.point()
        let firstRouteEnd = SyntheticCoordinates.point(latitudeOffset: 1, longitudeOffset: 1)
        let secondRouteStart = SyntheticCoordinates.point(latitudeOffset: 2, longitudeOffset: 2)
        let secondRouteEnd = SyntheticCoordinates.point(latitudeOffset: 2.01, longitudeOffset: 2.01)
        let excludedRouteStart = SyntheticCoordinates.point(latitudeOffset: 3, longitudeOffset: 3)
        let excludedRouteEnd = SyntheticCoordinates.point(latitudeOffset: 4, longitudeOffset: 4)
        let routes = [
            SavedTripRouteSegment(driveId: 10, points: [GeocodeLocation(latitude: firstRouteStart.latitude, longitude: firstRouteStart.longitude), GeocodeLocation(latitude: firstRouteEnd.latitude, longitude: firstRouteEnd.longitude)]),
            SavedTripRouteSegment(driveId: 11, points: [GeocodeLocation(latitude: secondRouteStart.latitude, longitude: secondRouteStart.longitude), GeocodeLocation(latitude: secondRouteEnd.latitude, longitude: secondRouteEnd.longitude)]),
            SavedTripRouteSegment(driveId: 99, points: [GeocodeLocation(latitude: excludedRouteStart.latitude, longitude: excludedRouteStart.longitude), GeocodeLocation(latitude: excludedRouteEnd.latitude, longitude: excludedRouteEnd.longitude)])
        ]
        let viewModel = TripDetailViewModel(
            dataProvider: FakeTripDataProvider(source: .roadTrip, routes: routes),
            tripStore: store,
            settingsStore: StaticTripSettingsStore()
        )

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)

        XCTAssertEqual(viewModel.state.routeSegments.map(\.driveId), [10, 11])
        XCTAssertEqual(viewModel.state.routeSegments.map(\.points.count), [2, 2])
    }

    func testTripRouteSegmentRejectsInvalidAndImplausibleCoordinates() {
        let validStart = SyntheticCoordinates.point()
        let implausiblePoint = SyntheticCoordinates.point(latitudeOffset: 5, longitudeOffset: 50)
        let validEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let segment = SavedTripRouteSegment(driveId: 10, positions: [
            DrivePosition(date: "2026-01-01T08:00:00Z", latitude: validStart.latitude, longitude: validStart.longitude),
            DrivePosition(date: "2026-01-01T08:01:00Z", latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude),
            DrivePosition(date: "2026-01-01T08:02:00Z", latitude: implausiblePoint.latitude, longitude: implausiblePoint.longitude),
            DrivePosition(date: "2026-01-01T08:10:00Z", latitude: validEnd.latitude, longitude: validEnd.longitude)
        ])

        XCTAssertEqual(segment.points, [
            GeocodeLocation(latitude: validStart.latitude, longitude: validStart.longitude),
            GeocodeLocation(latitude: validEnd.latitude, longitude: validEnd.longitude)
        ])
    }

    func testTripDataProviderUsesCachedRouteWithoutRequestingDriveDetail() async {
        let routeStart = SyntheticCoordinates.point()
        let routeEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let cache = InMemoryTripRouteCache(values: [
            "1:10": [
                GeocodeLocation(latitude: routeStart.latitude, longitude: routeStart.longitude),
                GeocodeLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
            ]
        ])
        let api = RouteAnalyticsAPI(details: [:])
        let provider = APITripDataProvider(api: api, routeCache: cache)

        let segments = await provider.routeSegments(carId: 1, driveIds: [10])
        let cached = await cache.value(carId: 1, driveId: 10)
        let requests = await api.requestedDriveIds()

        XCTAssertEqual(segments.first?.points, cached)
        XCTAssertEqual(requests, [])
    }

    func testTripDataProviderCachesSanitizedNetworkRoute() async {
        let cache = InMemoryTripRouteCache()
        let routeStart = SyntheticCoordinates.point()
        let routeEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let detail = DriveDetail(
            driveId: 10,
            positions: [
                DrivePosition(date: "2026-01-01T08:00:00Z", latitude: routeStart.latitude, longitude: routeStart.longitude),
                DrivePosition(date: "2026-01-01T08:10:00Z", latitude: routeEnd.latitude, longitude: routeEnd.longitude)
            ]
        )
        let api = RouteAnalyticsAPI(details: [10: detail])
        let provider = APITripDataProvider(api: api, routeCache: cache)

        let segments = await provider.routeSegments(carId: 1, driveIds: [10])
        let cached = await cache.value(carId: 1, driveId: 10)
        let requests = await api.requestedDriveIds()

        XCTAssertEqual(segments.first?.points.count, 2)
        XCTAssertEqual(cached, segments.first?.points)
        XCTAssertEqual(requests, [10])
    }

    func testTripDataProviderFallsBackToNetworkWhenRouteCacheFails() async {
        let routeStart = SyntheticCoordinates.point()
        let routeEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let detail = DriveDetail(
            driveId: 10,
            positions: [
                DrivePosition(date: "2026-01-01T08:00:00Z", latitude: routeStart.latitude, longitude: routeStart.longitude),
                DrivePosition(date: "2026-01-01T08:10:00Z", latitude: routeEnd.latitude, longitude: routeEnd.longitude)
            ]
        )
        let api = RouteAnalyticsAPI(details: [10: detail])
        let provider = APITripDataProvider(api: api, routeCache: FailingTripRouteCache())

        let segments = await provider.routeSegments(carId: 1, driveIds: [10])
        let requests = await api.requestedDriveIds()

        XCTAssertEqual(segments.first?.points.count, 2)
        XCTAssertEqual(requests, [10])
    }

    func testTripDetailRenameAndDeleteUpdateStore() async throws {
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: []
        )
        let viewModel = TripDetailViewModel(
            dataProvider: FakeTripDataProvider(source: .roadTrip),
            tripStore: store,
            settingsStore: StaticTripSettingsStore()
        )

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)
        await viewModel.rename("Renamed")
        let renamedTrips = try await store.savedTrips(carId: 1)
        XCTAssertEqual(renamedTrips.first?.name, "Renamed")

        await viewModel.deleteTrip()
        XCTAssertTrue(viewModel.state.justDeleted)
        let remainingTrips = try await store.savedTrips(carId: 1)
        XCTAssertTrue(remainingTrips.isEmpty)
    }

    func testRemovingFirstDriveRecalculatesDatesAndKeepsRenamedName() async throws {
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: "Original",
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(10), .charge(20), .drive(11)],
            consumedFingerprints: []
        )
        let viewModel = makeViewModel(store: store, source: .roadTrip)

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)
        await viewModel.rename("Renamed")
        await viewModel.removeLeg(.drive(10))

        let snapshots = try await store.savedTrips(carId: 1)
        let updated = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(updated.startDate, "2026-01-01T10:40:00Z")
        XCTAssertEqual(updated.endDate, "2026-01-01T12:10:00Z")
        XCTAssertEqual(updated.legs, [.charge(20), .drive(11)])
        XCTAssertEqual(viewModel.state.editableLegs.map(\.reference), [.charge(20), .drive(11)])
    }

    func testAddingNearbyUnusedLegsSortsAndRecalculatesTrip() async throws {
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T10:00:00Z",
            legs: [.drive(10)],
            consumedFingerprints: []
        )
        let viewModel = makeViewModel(store: store, source: .roadTrip)

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)
        XCTAssertEqual(Set(viewModel.state.availableLegs.map(\.reference)), [.charge(20), .drive(11)])
        await viewModel.addLegs([.drive(11), .charge(20)])

        let snapshots = try await store.savedTrips(carId: 1)
        let updated = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(updated.legs, [.drive(10), .charge(20), .drive(11)])
        XCTAssertEqual(updated.endDate, "2026-01-01T12:10:00Z")
        XCTAssertTrue(viewModel.state.availableLegs.isEmpty)
    }

    func testCandidatesExcludeUsedAndOutsideTwoDayWindowLegs() async throws {
        let source = TripSourceData(
            drives: TripSourceData.roadTrip.drives + [
                TripDrive(id: 99, startDate: "2026-01-10T08:00:00Z", endDate: "2026-01-10T09:00:00Z", distance: 20, durationMin: 60)
            ],
            charges: TripSourceData.roadTrip.charges,
            dcChargeIds: [20],
            units: .metric
        )
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T10:00:00Z",
            legs: [.drive(10)],
            consumedFingerprints: []
        )
        _ = try await store.saveTrip(
            carId: 1,
            name: "Other",
            startDate: "2026-01-01T10:05:00Z",
            endDate: "2026-01-01T10:35:00Z",
            legs: [.charge(20)],
            consumedFingerprints: []
        )
        let viewModel = makeViewModel(store: store, source: source)

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)

        XCTAssertEqual(viewModel.state.availableLegs.map(\.reference), [.drive(11)])
    }

    func testRemovingOnlyDriveDeletesTrip() async throws {
        let store = InMemoryTripStore()
        let saved = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T10:00:00Z",
            legs: [.drive(10)],
            consumedFingerprints: []
        )
        let viewModel = makeViewModel(store: store, source: .roadTrip)

        await viewModel.load(carId: 1, tripStartDate: saved.startDate)
        await viewModel.removeLeg(.drive(10))

        XCTAssertTrue(viewModel.state.justDeleted)
        let remaining = try await store.savedTrips(carId: 1)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMergingAdjacentTripsIncludesGapRecordsAndInheritsNameAndFingerprints() async throws {
        let store = InMemoryTripStore()
        let first = try await store.saveTrip(
            carId: 1,
            name: "Alpine Run",
            startDate: "2026-01-01T08:00:00Z",
            endDate: "2026-01-01T10:00:00Z",
            legs: [.drive(10)],
            consumedFingerprints: ["older-first"]
        )
        _ = try await store.saveTrip(
            carId: 1,
            name: nil,
            startDate: "2026-01-01T10:40:00Z",
            endDate: "2026-01-01T12:10:00Z",
            legs: [.drive(11)],
            consumedFingerprints: ["older-second"]
        )
        let viewModel = makeViewModel(store: store, source: .roadTrip)

        await viewModel.load(carId: 1, tripStartDate: first.startDate)
        let candidate = try XCTUnwrap(viewModel.state.mergeCandidates.first)
        await viewModel.merge(with: candidate)

        let snapshots = try await store.savedTrips(carId: 1)
        let merged = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(merged.name, "Alpine Run")
        XCTAssertEqual(merged.legs, [.drive(10), .charge(20), .drive(11)])
        XCTAssertTrue(merged.consumedFingerprints.isSuperset(of: [
            "older-first",
            "older-second",
            TripFingerprint.fingerprint(driveIds: [10]),
            TripFingerprint.fingerprint(driveIds: [11])
        ]))
        XCTAssertEqual(viewModel.state.savedTripId, merged.tripId)
        XCTAssertTrue(viewModel.state.mergeCandidates.isEmpty)
    }

    private func makeViewModel(store: InMemoryTripStore, source: TripSourceData) -> TripDetailViewModel {
        TripDetailViewModel(
            dataProvider: FakeTripDataProvider(source: source),
            tripStore: store,
            settingsStore: StaticTripSettingsStore()
        )
    }
}

private actor InMemoryTripRouteCache: TripRouteCaching {
    private var values: [String: [GeocodeLocation]]

    init(values: [String: [GeocodeLocation]] = [:]) {
        self.values = values
    }

    func points(carId: Int, driveId: Int) async throws -> [GeocodeLocation]? {
        values["\(carId):\(driveId)"]
    }

    func save(points: [GeocodeLocation], carId: Int, driveId: Int) async throws {
        values["\(carId):\(driveId)"] = points
    }

    func value(carId: Int, driveId: Int) -> [GeocodeLocation]? {
        values["\(carId):\(driveId)"]
    }
}

private struct FailingTripRouteCache: TripRouteCaching {
    func points(carId _: Int, driveId _: Int) async throws -> [GeocodeLocation]? {
        throw SQLiteError.executionFailed("Corrupt route cache")
    }

    func save(points _: [GeocodeLocation], carId _: Int, driveId _: Int) async throws {
        throw SQLiteError.executionFailed("Route cache is unavailable")
    }
}

private actor RouteAnalyticsAPI: AnalyticsAPIProviding {
    private let details: [Int: DriveDetail]
    private var requests: [Int] = []

    init(details: [Int: DriveDetail]) {
        self.details = details
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<DriveDetail> {
        requests.append(driveId)
        return details[driveId].map(APIResult.success) ?? .failure(.httpStatus(404))
    }

    func requestedDriveIds() -> [Int] { requests }
    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> { .failure(.httpStatus(404)) }
    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> { .failure(.httpStatus(404)) }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> { .success([]) }
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.httpStatus(404)) }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { .failure(.httpStatus(404)) }
}
