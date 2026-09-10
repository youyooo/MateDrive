import Foundation

public protocol TripPersisting: Sendable {
    func saveTrip(
        carId: Int,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws -> SavedTripSnapshot

    func savedTrips(carId: Int) async throws -> [SavedTripSnapshot]
    func renameTrip(tripId: String, name: String?) async throws
    func deleteTrip(tripId: String) async throws
    func replaceLegs(tripId: String, legs: [TripLegReference], consumedFingerprints: Set<String>) async throws
    func updateTrip(
        tripId: String,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws
    func mergeTrips(keptTripId: String, consumedTripId: String, merged: SavedTripSnapshot) async throws
}

public protocol TripRouteCaching: Sendable {
    func points(carId: Int, driveId: Int) async throws -> [GeocodeLocation]?
    func save(points: [GeocodeLocation], carId: Int, driveId: Int) async throws
}

public struct TripStore: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertRouteCache(_ record: TripRouteCacheRecord) async throws {
        try await database.run(
            "INSERT OR REPLACE INTO trip_route_cache (cache_key, payload_json, updated_at) VALUES (?, ?, ?);",
            bindings: [.text(record.cacheKey), .text(record.payloadJSON), .text(record.updatedAt)]
        )
    }

    public func routePoints(carId: Int, driveId: Int) async throws -> [GeocodeLocation]? {
        let rows = try await database.rows(
            "SELECT payload_json FROM trip_route_cache WHERE cache_key = ? LIMIT 1;",
            bindings: [.text(Self.routeCacheKey(carId: carId, driveId: driveId))]
        )
        guard let payload = rows.first?.first?.textValue else { return nil }
        return try JSONDecoder().decode(TripRouteCachePayload.self, from: Data(payload.utf8)).points
    }

    public func saveRoutePoints(_ points: [GeocodeLocation], carId: Int, driveId: Int) async throws {
        let payload = try JSONEncoder().encode(TripRouteCachePayload(points: points))
        guard let payloadJSON = String(data: payload, encoding: .utf8) else {
            throw SQLiteError.executionFailed("Unable to encode trip route cache")
        }
        try await upsertRouteCache(TripRouteCacheRecord(
            cacheKey: Self.routeCacheKey(carId: carId, driveId: driveId),
            payloadJSON: payloadJSON,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        ))
    }

    private static func routeCacheKey(carId: Int, driveId: Int) -> String {
        "car:\(carId):drive:\(driveId):v1"
    }

    public func upsertCountryCache(_ record: TripCountryCacheRecord) async throws {
        try await database.run(
            "INSERT OR REPLACE INTO trip_country_cache (cache_key, payload_json, updated_at) VALUES (?, ?, ?);",
            bindings: [.text(record.cacheKey), .text(record.payloadJSON), .text(record.updatedAt)]
        )
    }

    public func upsertTrip(_ record: SavedTripRecord) async throws {
        try await database.run(
            """
            INSERT OR REPLACE INTO saved_trips
            (trip_id, car_id, name, start_date, end_date)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [.text(record.tripId), .int(record.carId), .text(record.name), .text(record.startDate), .text(record.endDate)]
        )
    }

    public func upsertLeg(_ record: SavedTripLegRecord) async throws {
        try await database.run(
            "INSERT OR REPLACE INTO saved_trip_legs (leg_id, trip_id, sequence, payload_json) VALUES (?, ?, ?, ?);",
            bindings: [.text(record.legId), .text(record.tripId), .int(record.sequence), .text(record.payloadJSON)]
        )
    }

    public func markFingerprintConsumed(_ record: SavedTripConsumedFingerprintRecord) async throws {
        try await database.run(
            "INSERT OR IGNORE INTO saved_trip_consumed_fingerprints (trip_id, fingerprint) VALUES (?, ?);",
            bindings: [.text(record.tripId), .text(record.fingerprint)]
        )
    }
}

private struct TripRouteCachePayload: Codable {
    let points: [GeocodeLocation]
}

extension TripStore: TripPersisting {
    public func saveTrip(
        carId: Int,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws -> SavedTripSnapshot {
        let tripId = UUID().uuidString
        let snapshot = SavedTripSnapshot(
            tripId: tripId,
            carId: carId,
            name: normalizedName(name),
            startDate: startDate,
            endDate: endDate,
            legs: legs,
            consumedFingerprints: consumedFingerprints
        )
        try await write(snapshot)
        return snapshot
    }

    public func savedTrips(carId: Int) async throws -> [SavedTripSnapshot] {
        let rows = try await database.rows(
            """
            SELECT trip_id, car_id, name, start_date, end_date
            FROM saved_trips
            WHERE car_id = ?
            ORDER BY start_date DESC;
            """,
            bindings: [.int(carId)]
        )

        var snapshots: [SavedTripSnapshot] = []
        for row in rows {
            guard
                row.count >= 5,
                let tripId = row[0].textValue,
                let carId = row[1].intValue,
                let startDate = row[3].textValue,
                let endDate = row[4].textValue
            else {
                continue
            }
            let name = normalizedName(row[2].textValue)
            let legs = try await legsForTrip(tripId: tripId)
            let fingerprints = try await fingerprintsForTrip(tripId: tripId)
            snapshots.append(
                SavedTripSnapshot(
                    tripId: tripId,
                    carId: carId,
                    name: name,
                    startDate: startDate,
                    endDate: endDate,
                    legs: legs,
                    consumedFingerprints: fingerprints
                )
            )
        }
        return snapshots
    }

    public func renameTrip(tripId: String, name: String?) async throws {
        try await database.run(
            "UPDATE saved_trips SET name = ? WHERE trip_id = ?;",
            bindings: [.text(normalizedName(name) ?? ""), .text(tripId)]
        )
    }

    public func deleteTrip(tripId: String) async throws {
        try await database.run("DELETE FROM saved_trip_consumed_fingerprints WHERE trip_id = ?;", bindings: [.text(tripId)])
        try await database.run("DELETE FROM saved_trip_legs WHERE trip_id = ?;", bindings: [.text(tripId)])
        try await database.run("DELETE FROM saved_trips WHERE trip_id = ?;", bindings: [.text(tripId)])
    }

    public func replaceLegs(tripId: String, legs: [TripLegReference], consumedFingerprints: Set<String>) async throws {
        try await database.run("DELETE FROM saved_trip_legs WHERE trip_id = ?;", bindings: [.text(tripId)])
        for (index, leg) in legs.enumerated() {
            try await upsertLeg(
                SavedTripLegRecord(
                    legId: "\(tripId)-\(index)-\(leg.id)",
                    tripId: tripId,
                    sequence: index,
                    payloadJSON: payloadJSON(for: leg)
                )
            )
        }
        for fingerprint in consumedFingerprints {
            try await markFingerprintConsumed(SavedTripConsumedFingerprintRecord(tripId: tripId, fingerprint: fingerprint))
        }
    }

    public func updateTrip(
        tripId: String,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws {
        var commands = [
            SQLiteCommand(
                "UPDATE saved_trips SET name = ?, start_date = ?, end_date = ? WHERE trip_id = ?;",
                bindings: [.text(normalizedName(name) ?? ""), .text(startDate), .text(endDate), .text(tripId)]
            ),
            SQLiteCommand("DELETE FROM saved_trip_legs WHERE trip_id = ?;", bindings: [.text(tripId)])
        ]
        commands += try legs.enumerated().map { index, leg in
            SQLiteCommand(
                "INSERT INTO saved_trip_legs (leg_id, trip_id, sequence, payload_json) VALUES (?, ?, ?, ?);",
                bindings: [
                    .text("\(tripId)-\(index)-\(leg.id)"),
                    .text(tripId),
                    .int(index),
                    .text(try payloadJSON(for: leg))
                ]
            )
        }
        commands += consumedFingerprints.map { fingerprint in
            SQLiteCommand(
                "INSERT OR IGNORE INTO saved_trip_consumed_fingerprints (trip_id, fingerprint) VALUES (?, ?);",
                bindings: [.text(tripId), .text(fingerprint)]
            )
        }
        try await database.performTransaction(commands)
    }

    public func mergeTrips(keptTripId: String, consumedTripId: String, merged: SavedTripSnapshot) async throws {
        var commands = [
            SQLiteCommand("DELETE FROM saved_trip_consumed_fingerprints WHERE trip_id IN (?, ?);", bindings: [.text(keptTripId), .text(consumedTripId)]),
            SQLiteCommand("DELETE FROM saved_trip_legs WHERE trip_id IN (?, ?);", bindings: [.text(keptTripId), .text(consumedTripId)]),
            SQLiteCommand("DELETE FROM saved_trips WHERE trip_id IN (?, ?);", bindings: [.text(keptTripId), .text(consumedTripId)]),
            SQLiteCommand(
                "INSERT INTO saved_trips (trip_id, car_id, name, start_date, end_date) VALUES (?, ?, ?, ?, ?);",
                bindings: [.text(merged.tripId), .int(merged.carId), .text(merged.name ?? ""), .text(merged.startDate), .text(merged.endDate)]
            )
        ]
        commands += try merged.legs.enumerated().map { index, leg in
            SQLiteCommand(
                "INSERT INTO saved_trip_legs (leg_id, trip_id, sequence, payload_json) VALUES (?, ?, ?, ?);",
                bindings: [.text("\(merged.tripId)-\(index)-\(leg.id)"), .text(merged.tripId), .int(index), .text(try payloadJSON(for: leg))]
            )
        }
        commands += merged.consumedFingerprints.map {
            SQLiteCommand("INSERT INTO saved_trip_consumed_fingerprints (trip_id, fingerprint) VALUES (?, ?);", bindings: [.text(merged.tripId), .text($0)])
        }
        try await database.performTransaction(commands)
    }

    private func write(_ snapshot: SavedTripSnapshot) async throws {
        try await upsertTrip(
            SavedTripRecord(
                tripId: snapshot.tripId,
                carId: snapshot.carId,
                name: snapshot.name ?? "",
                startDate: snapshot.startDate,
                endDate: snapshot.endDate
            )
        )
        try await replaceLegs(
            tripId: snapshot.tripId,
            legs: snapshot.legs,
            consumedFingerprints: snapshot.consumedFingerprints
        )
    }

    private func legsForTrip(tripId: String) async throws -> [TripLegReference] {
        let rows = try await database.rows(
            """
            SELECT payload_json
            FROM saved_trip_legs
            WHERE trip_id = ?
            ORDER BY sequence;
            """,
            bindings: [.text(tripId)]
        )
        return try rows.compactMap { row in
            guard let payload = row.first?.textValue else {
                return nil
            }
            return try JSONDecoder().decode(TripLegReference.self, from: Data(payload.utf8))
        }
    }

    private func fingerprintsForTrip(tripId: String) async throws -> Set<String> {
        Set(
            try await database.textValues(
                """
                SELECT fingerprint
                FROM saved_trip_consumed_fingerprints
                WHERE trip_id = ?;
                """,
                bindings: [.text(tripId)]
            )
        )
    }

    private func payloadJSON(for leg: TripLegReference) throws -> String {
        let data = try JSONEncoder().encode(leg)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteError.executionFailed("Unable to encode trip leg")
        }
        return json
    }

    private func normalizedName(_ name: String?) -> String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

public struct DatabaseBackedTripStore: TripPersisting {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func saveTrip(
        carId: Int,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws -> SavedTripSnapshot {
        try await store().saveTrip(
            carId: carId,
            name: name,
            startDate: startDate,
            endDate: endDate,
            legs: legs,
            consumedFingerprints: consumedFingerprints
        )
    }

    public func savedTrips(carId: Int) async throws -> [SavedTripSnapshot] {
        try await store().savedTrips(carId: carId)
    }

    public func renameTrip(tripId: String, name: String?) async throws {
        try await store().renameTrip(tripId: tripId, name: name)
    }

    public func deleteTrip(tripId: String) async throws {
        try await store().deleteTrip(tripId: tripId)
    }

    public func replaceLegs(tripId: String, legs: [TripLegReference], consumedFingerprints: Set<String>) async throws {
        try await store().replaceLegs(tripId: tripId, legs: legs, consumedFingerprints: consumedFingerprints)
    }

    public func updateTrip(
        tripId: String,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String>
    ) async throws {
        try await store().updateTrip(
            tripId: tripId,
            name: name,
            startDate: startDate,
            endDate: endDate,
            legs: legs,
            consumedFingerprints: consumedFingerprints
        )
    }

    public func mergeTrips(keptTripId: String, consumedTripId: String, merged: SavedTripSnapshot) async throws {
        try await store().mergeTrips(keptTripId: keptTripId, consumedTripId: consumedTripId, merged: merged)
    }

    private func store() async throws -> TripStore {
        TripStore(database: try await databaseProvider.database())
    }
}

public struct DatabaseBackedTripRouteCache: TripRouteCaching {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func points(carId: Int, driveId: Int) async throws -> [GeocodeLocation]? {
        try await store().routePoints(carId: carId, driveId: driveId)
    }

    public func save(points: [GeocodeLocation], carId: Int, driveId: Int) async throws {
        try await store().saveRoutePoints(points, carId: carId, driveId: driveId)
    }

    private func store() async throws -> TripStore {
        TripStore(database: try await databaseProvider.database())
    }
}
