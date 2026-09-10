import Foundation

public protocol SentryAlertLogStoring: Sendable {
    func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord]
    func activeSessionStartedAt(carId: Int) async throws -> Int64?
    func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount]
    func upsert(_ record: SentryAlertLogRecord) async throws
}

public struct EmptySentryAlertLogStore: SentryAlertLogStoring {
    public init() {}
    public func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord] { [] }
    public func activeSessionStartedAt(carId: Int) async throws -> Int64? { nil }
    public func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount] { [] }
    public func upsert(_ record: SentryAlertLogRecord) async throws {}
}

public struct SentryAlertLogStore: SentryAlertLogStoring {
    private struct Payload: Codable {
        let sessionStartedAtMillis: Int64?
        let latitude: Double?
        let longitude: Double?
        let address: String?
    }

    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord] {
        let rows = try await database.rows(
            """
            SELECT event_id, car_id, occurred_at, payload_json
            FROM sentry_alert_log
            WHERE car_id = ?
            ORDER BY occurred_at DESC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap(Self.record(from:))
    }

    public func activeSessionStartedAt(carId: Int) async throws -> Int64? {
        nil
    }

    public func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount] {
        try await alertLogs(carId: carId)
            .filter { $0.detectedAtMillis >= sinceMillis }
            .reduce(into: [Int64: Int]()) { counts, record in
                counts[record.detectedAtMillis / 3_600_000, default: 0] += 1
            }
            .map { SentryHourlyCount(hourBucket: $0.key, count: $0.value) }
    }

    public func upsert(_ record: SentryAlertLogRecord) async throws {
        let payload = Payload(
            sessionStartedAtMillis: record.sessionStartedAtMillis,
            latitude: record.latitude,
            longitude: record.longitude,
            address: record.address
        )
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteError.executionFailed("Unable to encode sentry alert payload")
        }
        try await database.run(
            """
            INSERT OR REPLACE INTO sentry_alert_log
            (event_id, car_id, occurred_at, payload_json)
            VALUES (?, ?, ?, ?);
            """,
            bindings: [.text(record.id), .int(record.carId), .text(String(record.detectedAtMillis)), .text(json)]
        )
    }

    private static func record(from row: [SQLiteColumnValue]) -> SentryAlertLogRecord? {
        guard
            row.count >= 4,
            let id = row[0].textValue,
            let carId = row[1].intValue,
            let occurredAt = row[2].textValue,
            let detectedAtMillis = millis(from: occurredAt)
        else {
            return nil
        }

        let payload: Payload?
        if let json = row[3].textValue {
            payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        } else {
            payload = nil
        }

        return SentryAlertLogRecord(
            id: id,
            carId: carId,
            detectedAtMillis: detectedAtMillis,
            sessionStartedAtMillis: payload?.sessionStartedAtMillis,
            latitude: payload?.latitude,
            longitude: payload?.longitude,
            address: payload?.address
        )
    }

    private static func millis(from value: String) -> Int64? {
        if let raw = Int64(value) {
            return raw
        }
        guard let date = DomainDateParser.date(from: value) else {
            return nil
        }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

public struct DatabaseBackedSentryAlertLogStore: SentryAlertLogStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord] {
        try await store().alertLogs(carId: carId)
    }

    public func activeSessionStartedAt(carId: Int) async throws -> Int64? {
        try await store().activeSessionStartedAt(carId: carId)
    }

    public func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount] {
        try await store().hourlyCounts(carId: carId, sinceMillis: sinceMillis)
    }

    public func upsert(_ record: SentryAlertLogRecord) async throws {
        try await store().upsert(record)
    }

    private func store() async throws -> SentryAlertLogStore {
        SentryAlertLogStore(database: try await databaseProvider.database())
    }
}
