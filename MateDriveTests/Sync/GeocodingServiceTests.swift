import XCTest
@testable import MateDriveApp

final class GeocodingServiceTests: XCTestCase {
    func testCoordinateValidationRejectsInvalidValuesAndAcceptsLegalZeroAxis() {
        let point = SyntheticCoordinates.point()
        XCTAssertNil(GeoCoordinateValidator.location(latitude: nil, longitude: point.longitude))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: .nan, longitude: point.longitude))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: point.latitude, longitude: .infinity))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: SyntheticCoordinates.invalidLatitude, longitude: point.longitude))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: point.latitude, longitude: -SyntheticCoordinates.invalidLongitude))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude))
        XCTAssertNotNil(GeoCoordinateValidator.location(latitude: SyntheticCoordinates.zero.latitude, longitude: point.longitude))
        XCTAssertNotNil(GeoCoordinateValidator.location(latitude: point.latitude, longitude: SyntheticCoordinates.zero.longitude))
    }

    func testRouteSanitizerDropsImpossibleTimestampedJump() {
        let routeStart = SyntheticCoordinates.point()
        let impossibleJump = SyntheticCoordinates.point(latitudeOffset: 50, longitudeOffset: -100)
        let routeEnd = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.01)
        let route = GeoCoordinateValidator.sanitizedRoute([
            GeocodeRouteSample(latitude: routeStart.latitude, longitude: routeStart.longitude, date: "2026-07-11T08:00:00+08:00"),
            GeocodeRouteSample(latitude: impossibleJump.latitude, longitude: impossibleJump.longitude, date: "2026-07-11T08:00:10+08:00"),
            GeocodeRouteSample(latitude: routeEnd.latitude, longitude: routeEnd.longitude, date: "2026-07-11T08:01:00+08:00")
        ])

        XCTAssertEqual(route.count, 2)
        XCTAssertEqual(route.last?.latitude, routeEnd.latitude)
    }

    func testGridCoordinateUsesConfiguredPrecision() {
        XCTAssertEqual(GeocodeGrid.gridCoord(SyntheticCoordinates.positiveFractionalGridSample), 4885)
        XCTAssertEqual(GeocodeGrid.gridCoord(SyntheticCoordinates.negativeFractionalGridSample), -12241)
    }

    func testEnqueueDeduplicatesByGridAndSkipsCachedLocations() async throws {
        let cachedLocation = SyntheticCoordinates.point()
        let duplicateLocation = SyntheticCoordinates.point(latitudeOffset: 0.0001, longitudeOffset: 0.0001)
        let enqueuedLocation = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let store = InMemoryGeocodeQueueStore(cached: [
            GridKey(latitude: GeocodeGrid.gridCoord(cachedLocation.latitude), longitude: GeocodeGrid.gridCoord(cachedLocation.longitude))
        ])
        let service = GeocodingService(queueStore: store)

        let count = try await service.enqueueLocations(
            carId: 1,
            locations: [
                GeocodeLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude),
                GeocodeLocation(latitude: duplicateLocation.latitude, longitude: duplicateLocation.longitude),
                GeocodeLocation(latitude: enqueuedLocation.latitude, longitude: enqueuedLocation.longitude)
            ]
        )

        XCTAssertEqual(count, 1)
        let enqueued = await store.enqueuedSnapshot()
        XCTAssertEqual(enqueued.map(\.gridLatitude), [GeocodeGrid.gridCoord(enqueuedLocation.latitude)])
    }

    func testReverseGeocodeCachesSuccessfulResult() async throws {
        let store = InMemoryGeocodeQueueStore()
        let api = CountingReverseGeocoder()
        let service = GeocodingService(queueStore: store, reverseGeocoder: api)

        let firstCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let secondCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.00201, longitudeOffset: 0.00201)
        let cachedLocation = SyntheticCoordinates.point(latitudeOffset: 0.00202, longitudeOffset: 0.00202)
        let first = await service.reverseGeocode(latitude: firstCoordinate.latitude, longitude: firstCoordinate.longitude)
        let second = await service.reverseGeocode(latitude: secondCoordinate.latitude, longitude: secondCoordinate.longitude)

        guard case let .success(firstLocation) = first, case let .success(secondLocation) = second else {
            return XCTFail("Expected cached geocoding results")
        }
        XCTAssertEqual(firstLocation.countryCode, "CN")
        XCTAssertEqual(secondLocation.countryCode, "CN")
        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
        let cached = await service.cachedLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude)
        XCTAssertEqual(cached?.countryCode, "CN")
    }

    func testGeocodeStorePersistsStructuredLocationByGrid() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute(
            "CREATE TABLE geocode_cache (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, payload_json TEXT NOT NULL, updated_at TEXT NOT NULL);"
        )
        let store = GeocodeStore(database: database)
        let location = GeocodedLocation(address: "长沙市", countryCode: "CN", countryName: "China", regionName: "Hunan", city: "Changsha")

        let coordinate = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        try await store.save(location: location, latitude: coordinate.latitude, longitude: coordinate.longitude)
        let restored = try await store.cachedLocation(gridLatitude: GeocodeGrid.gridCoord(coordinate.latitude), gridLongitude: GeocodeGrid.gridCoord(coordinate.longitude))

        XCTAssertEqual(restored, location)
    }

    func testGeocodeStoreReportsCacheAndPendingQueueHealth() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("CREATE TABLE geocode_cache (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, payload_json TEXT NOT NULL, updated_at TEXT NOT NULL);")
        try await database.execute("CREATE TABLE geocode_queue (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, created_at TEXT NOT NULL);")
        let store = GeocodeStore(database: database)
        let cachedCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let pendingCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        try await store.save(location: GeocodedLocation(countryCode: "CN"), latitude: cachedCoordinate.latitude, longitude: cachedCoordinate.longitude)
        try await store.enqueue(GeocodeQueueRecord(cacheKey: "1210:3410", latitude: pendingCoordinate.latitude, longitude: pendingCoordinate.longitude, createdAt: "2026-07-11T10:00:00Z"))

        let health = try await store.health()

        XCTAssertEqual(health.cachedLocationCount, 1)
        XCTAssertEqual(health.pendingLocationCount, 1)
        XCTAssertNotNil(health.lastUpdatedAt)
    }

    func testQueueProcessorRemovesSuccessAndRetainsFailure() async throws {
        let store = InMemoryGeocodeQueueStore()
        let successfulCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let failedCoordinate = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        try await store.enqueue([
            GeocodeQueueItem(gridLatitude: GeocodeGrid.gridCoord(successfulCoordinate.latitude), gridLongitude: GeocodeGrid.gridCoord(successfulCoordinate.longitude), carId: 1, latitude: successfulCoordinate.latitude, longitude: successfulCoordinate.longitude, addedAtMilliseconds: 1),
            GeocodeQueueItem(gridLatitude: GeocodeGrid.gridCoord(failedCoordinate.latitude), gridLongitude: GeocodeGrid.gridCoord(failedCoordinate.longitude), carId: 1, latitude: failedCoordinate.latitude, longitude: failedCoordinate.longitude, addedAtMilliseconds: 2)
        ])
        let api = SequencedReverseGeocoder(results: [
            .success(GeocodedLocation(countryCode: "CN")),
            .failure(.network("offline"))
        ])
        let service = GeocodingService(queueStore: store, reverseGeocoder: api)

        let report = await service.processPending(limit: 6)

        XCTAssertEqual(report, GeocodeQueueProcessingReport(attemptedCount: 2, completedCount: 1, failedCount: 1))
        let remaining = await store.enqueuedSnapshot()
        XCTAssertEqual(remaining.map(\.gridLatitude), [GeocodeGrid.gridCoord(failedCoordinate.latitude)])
    }

    func testQueueProcessorHonorsBatchLimit() async throws {
        let store = InMemoryGeocodeQueueStore()
        try await store.enqueue((0..<8).map {
            GeocodeQueueItem(gridLatitude: $0, gridLongitude: $0, carId: 1, latitude: Double($0) + 1, longitude: Double($0) + 1, addedAtMilliseconds: Int64($0))
        })
        let api = CountingReverseGeocoder()
        let service = GeocodingService(queueStore: store, reverseGeocoder: api)

        let report = await service.processPending(limit: 3)

        XCTAssertEqual(report.attemptedCount, 3)
        let remainingCount = await store.enqueuedSnapshot().count
        XCTAssertEqual(remainingCount, 5)
    }

    func testDashboardCacheOnlyLocationLookupQueuesMissingAddressWithoutUsingNetwork() async {
        let store = InMemoryGeocodeQueueStore()
        let api = CountingReverseGeocoder()
        let resolver = CachedDashboardLocationResolver(
            queueStore: store,
            reverseGeocoder: api,
            allowsNetworkLookup: false
        )
        let coordinate = SyntheticCoordinates.point(latitudeOffset: 0.04, longitudeOffset: 0.04)

        let address = await resolver.address(
            carId: 1,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        XCTAssertNil(address)
        let requestCount = await api.requestCount
        let pendingCount = await store.enqueuedSnapshot().count
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(pendingCount, 1)
    }
}

private actor InMemoryGeocodeQueueStore: GeocodeQueueStoring {
    private var cached: Set<GridKey>
    private(set) var enqueued: [GeocodeQueueItem] = []

    init(cached: Set<GridKey> = []) {
        self.cached = cached
    }

    func cachedLocation(gridLatitude: Int, gridLongitude: Int) async throws -> GeocodedLocation? {
        let key = GridKey(latitude: gridLatitude, longitude: gridLongitude)
        return locations[key] ?? (cached.contains(key) ? GeocodedLocation(countryCode: "FR") : nil)
    }

    func enqueue(_ items: [GeocodeQueueItem]) async throws {
        enqueued.append(contentsOf: items)
    }

    func save(location: GeocodedLocation, latitude: Double, longitude: Double) async throws {
        cached.insert(GridKey(latitude: GeocodeGrid.gridCoord(latitude), longitude: GeocodeGrid.gridCoord(longitude)))
        locations[GridKey(latitude: GeocodeGrid.gridCoord(latitude), longitude: GeocodeGrid.gridCoord(longitude))] = location
    }

    func pending(limit: Int) async throws -> [GeocodeQueueItem] {
        Array(enqueued.prefix(limit))
    }

    func removePending(gridLatitude: Int, gridLongitude: Int) async throws {
        enqueued.removeAll { $0.gridLatitude == gridLatitude && $0.gridLongitude == gridLongitude }
    }

    func enqueuedSnapshot() -> [GeocodeQueueItem] {
        enqueued
    }

    private var locations: [GridKey: GeocodedLocation] = [:]
}

private actor CountingReverseGeocoder: ReverseGeocodingAPI {
    private(set) var requestCount = 0
    func reverseGeocode(latitude _: Double, longitude _: Double) async -> APIResult<GeocodedLocation> {
        requestCount += 1
        return .success(GeocodedLocation(countryCode: "CN", countryName: "China", regionName: "Hunan"))
    }
}

private actor SequencedReverseGeocoder: ReverseGeocodingAPI {
    private var results: [APIResult<GeocodedLocation>]
    init(results: [APIResult<GeocodedLocation>]) { self.results = results }
    func reverseGeocode(latitude _: Double, longitude _: Double) async -> APIResult<GeocodedLocation> {
        results.isEmpty ? .failure(.emptyBody) : results.removeFirst()
    }
}

private struct GridKey: Hashable {
    let latitude: Int
    let longitude: Int
}
