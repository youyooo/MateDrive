import XCTest
@testable import MateDroidIOS

final class GeocodingServiceTests: XCTestCase {
    func testCoordinateValidationRejectsInvalidValuesAndAcceptsLegalZeroAxis() {
        XCTAssertNil(GeoCoordinateValidator.location(latitude: nil, longitude: 1))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: .nan, longitude: 1))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: 1, longitude: .infinity))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: 91, longitude: 1))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: 1, longitude: -181))
        XCTAssertNil(GeoCoordinateValidator.location(latitude: 0, longitude: 0))
        XCTAssertNotNil(GeoCoordinateValidator.location(latitude: 0, longitude: 10))
        XCTAssertNotNil(GeoCoordinateValidator.location(latitude: 10, longitude: 0))
    }

    func testRouteSanitizerDropsImpossibleTimestampedJump() {
        let route = GeoCoordinateValidator.sanitizedRoute([
            GeocodeRouteSample(latitude: 28.20, longitude: 112.85, date: "2026-07-11T08:00:00+08:00"),
            GeocodeRouteSample(latitude: 40.71, longitude: -74.00, date: "2026-07-11T08:00:10+08:00"),
            GeocodeRouteSample(latitude: 28.21, longitude: 112.86, date: "2026-07-11T08:01:00+08:00")
        ])

        XCTAssertEqual(route.count, 2)
        XCTAssertEqual(route.last?.latitude, 28.21)
    }

    func testGridCoordMatchesAndroidPrecision() {
        XCTAssertEqual(GeocodeGrid.gridCoord(48.8566), 4885)
        XCTAssertEqual(GeocodeGrid.gridCoord(-122.4194), -12241)
    }

    func testEnqueueDeduplicatesByGridAndSkipsCachedLocations() async throws {
        let store = InMemoryGeocodeQueueStore(cached: [
            GridKey(latitude: 4885, longitude: 235)
        ])
        let service = GeocodingService(queueStore: store)

        let count = try await service.enqueueLocations(
            carId: 1,
            locations: [
                GeocodeLocation(latitude: 48.8566, longitude: 2.3522),
                GeocodeLocation(latitude: 48.8567, longitude: 2.3523),
                GeocodeLocation(latitude: 49.0000, longitude: 2.0000)
            ]
        )

        XCTAssertEqual(count, 1)
        let enqueued = await store.enqueuedSnapshot()
        XCTAssertEqual(enqueued.map(\.gridLatitude), [4900])
    }

    func testReverseGeocodeCachesSuccessfulResult() async throws {
        let store = InMemoryGeocodeQueueStore()
        let api = CountingReverseGeocoder()
        let service = GeocodingService(queueStore: store, reverseGeocoder: api)

        let first = await service.reverseGeocode(latitude: 28.2278, longitude: 112.9388)
        let second = await service.reverseGeocode(latitude: 28.22781, longitude: 112.93881)

        guard case let .success(firstLocation) = first, case let .success(secondLocation) = second else {
            return XCTFail("Expected cached geocoding results")
        }
        XCTAssertEqual(firstLocation.countryCode, "CN")
        XCTAssertEqual(secondLocation.countryCode, "CN")
        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
        let cached = await service.cachedLocation(latitude: 28.22782, longitude: 112.93882)
        XCTAssertEqual(cached?.countryCode, "CN")
    }

    func testGeocodeStorePersistsStructuredLocationByGrid() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute(
            "CREATE TABLE geocode_cache (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, payload_json TEXT NOT NULL, updated_at TEXT NOT NULL);"
        )
        let store = GeocodeStore(database: database)
        let location = GeocodedLocation(address: "长沙市", countryCode: "CN", countryName: "China", regionName: "Hunan", city: "Changsha")

        try await store.save(location: location, latitude: 28.2278, longitude: 112.9388)
        let restored = try await store.cachedLocation(gridLatitude: 2822, gridLongitude: 11293)

        XCTAssertEqual(restored, location)
    }

    func testGeocodeStoreReportsCacheAndPendingQueueHealth() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("CREATE TABLE geocode_cache (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, payload_json TEXT NOT NULL, updated_at TEXT NOT NULL);")
        try await database.execute("CREATE TABLE geocode_queue (cache_key TEXT PRIMARY KEY, latitude REAL NOT NULL, longitude REAL NOT NULL, created_at TEXT NOT NULL);")
        let store = GeocodeStore(database: database)
        try await store.save(location: GeocodedLocation(countryCode: "CN"), latitude: 28.2278, longitude: 112.9388)
        try await store.enqueue(GeocodeQueueRecord(cacheKey: "3000:12000", latitude: 30, longitude: 120, createdAt: "2026-07-11T10:00:00Z"))

        let health = try await store.health()

        XCTAssertEqual(health.cachedLocationCount, 1)
        XCTAssertEqual(health.pendingLocationCount, 1)
        XCTAssertNotNil(health.lastUpdatedAt)
    }

    func testQueueProcessorRemovesSuccessAndRetainsFailure() async throws {
        let store = InMemoryGeocodeQueueStore()
        try await store.enqueue([
            GeocodeQueueItem(gridLatitude: 2822, gridLongitude: 11293, carId: 1, latitude: 28.2278, longitude: 112.9388, addedAtMilliseconds: 1),
            GeocodeQueueItem(gridLatitude: 3000, gridLongitude: 12000, carId: 1, latitude: 30, longitude: 120, addedAtMilliseconds: 2)
        ])
        let api = SequencedReverseGeocoder(results: [
            .success(GeocodedLocation(countryCode: "CN")),
            .failure(.network("offline"))
        ])
        let service = GeocodingService(queueStore: store, reverseGeocoder: api)

        let report = await service.processPending(limit: 6)

        XCTAssertEqual(report, GeocodeQueueProcessingReport(attemptedCount: 2, completedCount: 1, failedCount: 1))
        let remaining = await store.enqueuedSnapshot()
        XCTAssertEqual(remaining.map(\.gridLatitude), [3000])
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
