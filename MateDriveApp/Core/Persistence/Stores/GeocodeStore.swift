import Foundation

public struct GeographyCacheHealth: Equatable, Sendable {
    public let cachedLocationCount: Int
    public let pendingLocationCount: Int
    public let lastUpdatedAt: String?

    public init(cachedLocationCount: Int, pendingLocationCount: Int, lastUpdatedAt: String?) {
        self.cachedLocationCount = cachedLocationCount
        self.pendingLocationCount = pendingLocationCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public protocol GeographyCacheHealthProviding: Sendable {
    func health() async throws -> GeographyCacheHealth
}

public struct EmptyGeographyCacheHealthProvider: GeographyCacheHealthProviding {
    public init() {}
    public func health() async throws -> GeographyCacheHealth { GeographyCacheHealth(cachedLocationCount: 0, pendingLocationCount: 0, lastUpdatedAt: nil) }
}

public struct GeocodeStore: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertCache(_ record: GeocodeCacheRecord) async throws {
        try await database.run(
            """
            INSERT OR REPLACE INTO geocode_cache
            (cache_key, latitude, longitude, payload_json, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [.text(record.cacheKey), .double(record.latitude), .double(record.longitude), .text(record.payloadJSON), .text(record.updatedAt)]
        )
    }

    public func enqueue(_ record: GeocodeQueueRecord) async throws {
        try await database.run(
            """
            INSERT OR IGNORE INTO geocode_queue
            (cache_key, latitude, longitude, created_at)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [.text(record.cacheKey), .double(record.latitude), .double(record.longitude), .text(record.createdAt)]
        )
    }

    public func saveProgress(_ record: GeocodeProgressRecord) async throws {
        try await database.run(
            """
            INSERT OR REPLACE INTO geocode_progress
            (car_id, last_processed_at)
            VALUES (?, ?);
            """,
            bindings: [.int(record.carId), record.lastProcessedAt.map(SQLiteValue.text) ?? .null]
        )
    }

    public func cachedLocation(gridLatitude: Int, gridLongitude: Int) async throws -> GeocodedLocation? {
        let rows = try await database.rows(
            "SELECT payload_json FROM geocode_cache WHERE cache_key = ? LIMIT 1;",
            bindings: [.text("\(gridLatitude):\(gridLongitude)")]
        )
        guard let payload = rows.first?.first?.textValue else { return nil }
        return try JSONDecoder().decode(GeocodedLocation.self, from: Data(payload.utf8))
    }

    public func save(location: GeocodedLocation, latitude: Double, longitude: Double) async throws {
        let data = try JSONEncoder().encode(location)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw SQLiteError.executionFailed("Unable to encode geocoded location")
        }
        try await upsertCache(GeocodeCacheRecord(
            cacheKey: "\(GeocodeGrid.gridCoord(latitude)):\(GeocodeGrid.gridCoord(longitude))",
            latitude: latitude,
            longitude: longitude,
            payloadJSON: payload,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
    }

    public func health() async throws -> GeographyCacheHealth {
        let cached = try await database.intValues("SELECT COUNT(*) FROM geocode_cache;").first ?? 0
        let pending = try await database.intValues("SELECT COUNT(*) FROM geocode_queue;").first ?? 0
        let updated = try await database.textValues("SELECT MAX(updated_at) FROM geocode_cache WHERE updated_at IS NOT NULL;").first
        return GeographyCacheHealth(cachedLocationCount: cached, pendingLocationCount: pending, lastUpdatedAt: updated)
    }

    public func pending(limit: Int) async throws -> [GeocodeQueueItem] {
        let rows = try await database.rows(
            "SELECT cache_key, latitude, longitude, created_at FROM geocode_queue ORDER BY created_at LIMIT ?;",
            bindings: [.int(max(limit, 0))]
        )
        return rows.compactMap { row in
            guard row.count >= 4, let key = row[0].textValue, let latitude = row[1].doubleValue, let longitude = row[2].doubleValue else { return nil }
            let parts = key.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            let addedAt = row[3].textValue.flatMap(DomainDateParser.date(from:)).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
            return GeocodeQueueItem(gridLatitude: parts[0], gridLongitude: parts[1], carId: 0, latitude: latitude, longitude: longitude, addedAtMilliseconds: addedAt)
        }
    }

    public func removePending(gridLatitude: Int, gridLongitude: Int) async throws {
        try await database.run("DELETE FROM geocode_queue WHERE cache_key = ?;", bindings: [.text("\(gridLatitude):\(gridLongitude)")])
    }
}

public struct DatabaseBackedGeocodeQueueStore: GeocodeQueueStoring, GeographyCacheHealthProviding {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func cachedLocation(gridLatitude: Int, gridLongitude: Int) async throws -> GeocodedLocation? {
        try await store().cachedLocation(gridLatitude: gridLatitude, gridLongitude: gridLongitude)
    }

    public func enqueue(_ items: [GeocodeQueueItem]) async throws {
        for item in items {
            try await store().enqueue(GeocodeQueueRecord(
                cacheKey: "\(item.gridLatitude):\(item.gridLongitude)",
                latitude: item.latitude,
                longitude: item.longitude,
                createdAt: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(item.addedAtMilliseconds) / 1000))
            ))
        }
    }

    public func save(location: GeocodedLocation, latitude: Double, longitude: Double) async throws {
        try await store().save(location: location, latitude: latitude, longitude: longitude)
    }

    public func health() async throws -> GeographyCacheHealth {
        try await store().health()
    }

    public func pending(limit: Int) async throws -> [GeocodeQueueItem] {
        try await store().pending(limit: limit)
    }

    public func removePending(gridLatitude: Int, gridLongitude: Int) async throws {
        try await store().removePending(gridLatitude: gridLatitude, gridLongitude: gridLongitude)
    }

    private func store() async throws -> GeocodeStore {
        GeocodeStore(database: try await databaseProvider.database())
    }
}
