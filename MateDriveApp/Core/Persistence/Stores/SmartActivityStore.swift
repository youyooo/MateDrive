import Foundation

public protocol SmartActivitySessionStoring: Sendable {
    func knownCarIds() async throws -> [Int]
    func sessions(carId: Int) async throws -> [SmartActivitySession]
    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession?
    func replace(carId: Int, sessions: [SmartActivitySession]) async throws
    func derivationFingerprint(carId: Int) async throws -> String?
    func replace(carId: Int, sessions: [SmartActivitySession], derivationFingerprint: String) async throws
    func removeDerivedSessions(carId: Int) async throws
    func removeDerivedSessions() async throws
}

public extension SmartActivitySessionStoring {
    func knownCarIds() async throws -> [Int] { [] }

    func derivationFingerprint(carId: Int) async throws -> String? {
        try await sessions(carId: carId).first?.derivationFingerprint
    }

    func replace(
        carId: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint _: String
    ) async throws {
        try await replace(carId: carId, sessions: sessions)
    }

    func removeDerivedSessions(carId: Int) async throws {
        try await replace(carId: carId, sessions: [])
    }
}

public protocol ActivityLabelOverrideStoring: Sendable {
    func knownCarIds() async throws -> [Int]
    func overrides(carId: Int) async throws -> [ActivityLabelOverride]
    func override(id: String) async throws -> ActivityLabelOverride?
    func save(_ value: ActivityLabelOverride) async throws
    func delete(id: String) async throws
    func removeAll() async throws
}

public extension ActivityLabelOverrideStoring {
    func knownCarIds() async throws -> [Int] { [] }
}

public struct SmartActivityStore: SmartActivitySessionStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func knownCarIds() async throws -> [Int] {
        let rows = try await database.rows(
            """
            SELECT car_id FROM vehicle_activity_sessions
            UNION
            SELECT car_id FROM smart_activity_index_state
            ORDER BY car_id ASC;
            """
        )
        return rows.compactMap { $0.first?.intValue }
    }

    public func sessions(carId: Int) async throws -> [SmartActivitySession] {
        let rows = try await database.rows(
            """
            SELECT session_id, car_id, start_date, payload_json
            FROM vehicle_activity_sessions
            WHERE car_id = ?
            ORDER BY start_date DESC, session_id ASC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap(Self.session)
    }

    public func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        let rows = try await database.rows(
            """
            SELECT session_id, car_id, start_date, payload_json
            FROM vehicle_activity_sessions
            WHERE car_id = ? AND session_id = ?
            LIMIT 1;
            """,
            bindings: [.int(carId), .text(sessionId)]
        )
        return rows.first.flatMap(Self.session)
    }

    public func derivationFingerprint(carId: Int) async throws -> String? {
        let rows = try await database.rows(
            """
            SELECT derivation_fingerprint
            FROM smart_activity_index_state
            WHERE car_id = ?
            LIMIT 1;
            """,
            bindings: [.int(carId)]
        )
        return rows.first?.first?.textValue
    }

    public func replace(carId: Int, sessions: [SmartActivitySession]) async throws {
        let fingerprint = sessions.first?.derivationFingerprint ?? ""
        try await replace(
            carId: carId,
            sessions: sessions,
            derivationFingerprint: fingerprint
        )
    }

    public func replace(
        carId: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint: String
    ) async throws {
        guard sessions.allSatisfy({ $0.carId == carId }) else {
            throw SQLiteError.executionFailed("Smart activity replacement contains a session for another car")
        }

        let orderedSessions = sessions.sorted {
            if $0.startDate == $1.startDate {
                return $0.id < $1.id
            }
            return $0.startDate < $1.startDate
        }
        let updatedAt = SmartActivityPersistenceCoding.dateString(Date())
        var commands = [
            SQLiteCommand(
                "DELETE FROM vehicle_activity_sessions WHERE car_id = ?;",
                bindings: [.int(carId)]
            )
        ]
        for session in orderedSessions {
            let payload = try SmartActivityPersistenceCoding.encode(session)
            let purpose = session.classification?.purpose ?? session.provisionalKind
            commands.append(SQLiteCommand(
                """
                INSERT INTO vehicle_activity_sessions
                (session_id, car_id, start_date, end_date, place_key, purpose, confidence,
                 quality, derivation_version, source_fingerprint, derivation_fingerprint,
                 payload_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(session.id),
                    .int(session.carId),
                    .text(SmartActivityPersistenceCoding.dateString(session.startDate)),
                    session.endDate.map { .text(SmartActivityPersistenceCoding.dateString($0)) } ?? .null,
                    .text(session.placeKey),
                    .text(purpose.rawValue),
                    session.classification.map { .double($0.confidence) } ?? .null,
                    .text(session.quality.rawValue),
                    .int(session.derivationVersion),
                    .text(session.sourceFingerprint),
                    .text(session.derivationFingerprint),
                    .text(payload),
                    .text(updatedAt)
                ]
            ))
        }
        commands.append(SQLiteCommand(
            """
            INSERT INTO smart_activity_index_state (car_id, derivation_fingerprint, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(car_id) DO UPDATE SET
              derivation_fingerprint = excluded.derivation_fingerprint,
              updated_at = excluded.updated_at;
            """,
            bindings: [.int(carId), .text(derivationFingerprint), .text(updatedAt)]
        ))
        try await database.performTransaction(commands)
    }

    public func removeDerivedSessions() async throws {
        try await database.performTransaction([
            SQLiteCommand("DELETE FROM vehicle_activity_sessions;"),
            SQLiteCommand("DELETE FROM smart_activity_index_state;")
        ])
    }

    public func removeDerivedSessions(carId: Int) async throws {
        try await database.performTransaction([
            SQLiteCommand(
                "DELETE FROM vehicle_activity_sessions WHERE car_id = ?;",
                bindings: [.int(carId)]
            ),
            SQLiteCommand(
                "DELETE FROM smart_activity_index_state WHERE car_id = ?;",
                bindings: [.int(carId)]
            )
        ])
    }

    private static func session(_ row: [SQLiteColumnValue]) -> SmartActivitySession? {
        guard row.count == 4,
              let sessionId = row[0].textValue,
              let carId = row[1].intValue,
              let startDateValue = row[2].textValue,
              let startDate = SmartActivityPersistenceCoding.date(startDateValue),
              let payload = row[3].textValue,
              let session = try? SmartActivityPersistenceCoding.decode(SmartActivitySession.self, from: payload),
              session.id == sessionId,
              session.carId == carId,
              session.startDate == startDate
        else { return nil }
        return session
    }
}

public struct ActivityLabelOverrideStore: ActivityLabelOverrideStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func knownCarIds() async throws -> [Int] {
        let rows = try await database.rows(
            "SELECT DISTINCT car_id FROM activity_label_overrides ORDER BY car_id ASC;"
        )
        return rows.compactMap { $0.first?.intValue }
    }

    public func overrides(carId: Int) async throws -> [ActivityLabelOverride] {
        let rows = try await database.rows(
            """
            SELECT override_id, car_id, session_id, place_key, scope, purpose,
                   custom_name, icon, color_hex, start_minute, end_minute, updated_at
            FROM activity_label_overrides
            WHERE car_id = ?
            ORDER BY updated_at DESC, override_id ASC;
            """,
            bindings: [.int(carId)]
        )
        return rows.compactMap(Self.value)
    }

    public func override(id: String) async throws -> ActivityLabelOverride? {
        let rows = try await database.rows(
            """
            SELECT override_id, car_id, session_id, place_key, scope, purpose,
                   custom_name, icon, color_hex, start_minute, end_minute, updated_at
            FROM activity_label_overrides
            WHERE override_id = ?
            LIMIT 1;
            """,
            bindings: [.text(id)]
        )
        return rows.first.flatMap(Self.value)
    }

    public func save(_ value: ActivityLabelOverride) async throws {
        try await database.run(
            """
            INSERT INTO activity_label_overrides
            (override_id, car_id, session_id, place_key, scope, purpose, custom_name,
             icon, color_hex, start_minute, end_minute, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(override_id) DO UPDATE SET
              car_id = excluded.car_id,
              session_id = excluded.session_id,
              place_key = excluded.place_key,
              scope = excluded.scope,
              purpose = excluded.purpose,
              custom_name = excluded.custom_name,
              icon = excluded.icon,
              color_hex = excluded.color_hex,
              start_minute = excluded.start_minute,
              end_minute = excluded.end_minute,
              updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(value.id),
                .int(value.carId),
                value.sessionId.map(SQLiteValue.text) ?? .null,
                value.placeKey.map(SQLiteValue.text) ?? .null,
                .text(value.scope.rawValue),
                .text(value.purpose.rawValue),
                value.customName.map(SQLiteValue.text) ?? .null,
                .text(value.icon),
                .text(value.colorHex),
                value.startMinute.map(SQLiteValue.int) ?? .null,
                value.endMinute.map(SQLiteValue.int) ?? .null,
                .text(SmartActivityPersistenceCoding.dateString(value.updatedAt))
            ]
        )
    }

    public func delete(id: String) async throws {
        try await database.run(
            "DELETE FROM activity_label_overrides WHERE override_id = ?;",
            bindings: [.text(id)]
        )
    }

    public func removeAll() async throws {
        try await database.run("DELETE FROM activity_label_overrides;")
    }

    private static func value(_ row: [SQLiteColumnValue]) -> ActivityLabelOverride? {
        guard row.count == 12,
              let id = row[0].textValue,
              let carId = row[1].intValue,
              let scopeValue = row[4].textValue,
              let scope = ActivityLabelScope(rawValue: scopeValue),
              let purposeValue = row[5].textValue,
              let purpose = SmartActivityPurpose(rawValue: purposeValue),
              let icon = row[7].textValue,
              let colorHex = row[8].textValue,
              let updatedAtValue = row[11].textValue,
              let updatedAt = SmartActivityPersistenceCoding.date(updatedAtValue)
        else { return nil }
        return ActivityLabelOverride(
            id: id,
            carId: carId,
            sessionId: row[2].textValue,
            placeKey: row[3].textValue,
            scope: scope,
            purpose: purpose,
            customName: row[6].textValue,
            icon: icon,
            colorHex: colorHex,
            startMinute: row[9].intValue,
            endMinute: row[10].intValue,
            updatedAt: updatedAt
        )
    }
}

public struct DatabaseBackedSmartActivityStore: SmartActivitySessionStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func knownCarIds() async throws -> [Int] {
        try await SmartActivityStore(database: databaseProvider.database()).knownCarIds()
    }

    public func sessions(carId: Int) async throws -> [SmartActivitySession] {
        try await SmartActivityStore(database: databaseProvider.database()).sessions(carId: carId)
    }

    public func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        try await SmartActivityStore(database: databaseProvider.database())
            .session(carId: carId, sessionId: sessionId)
    }

    public func derivationFingerprint(carId: Int) async throws -> String? {
        try await SmartActivityStore(database: databaseProvider.database())
            .derivationFingerprint(carId: carId)
    }

    public func replace(carId: Int, sessions: [SmartActivitySession]) async throws {
        try await SmartActivityStore(database: databaseProvider.database()).replace(carId: carId, sessions: sessions)
    }

    public func replace(
        carId: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint: String
    ) async throws {
        try await SmartActivityStore(database: databaseProvider.database()).replace(
            carId: carId,
            sessions: sessions,
            derivationFingerprint: derivationFingerprint
        )
    }

    public func removeDerivedSessions() async throws {
        try await SmartActivityStore(database: databaseProvider.database()).removeDerivedSessions()
    }

    public func removeDerivedSessions(carId: Int) async throws {
        try await SmartActivityStore(database: databaseProvider.database())
            .removeDerivedSessions(carId: carId)
    }
}

public struct DatabaseBackedActivityLabelOverrideStore: ActivityLabelOverrideStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func knownCarIds() async throws -> [Int] {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).knownCarIds()
    }

    public func overrides(carId: Int) async throws -> [ActivityLabelOverride] {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).overrides(carId: carId)
    }

    public func override(id: String) async throws -> ActivityLabelOverride? {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).override(id: id)
    }

    public func save(_ value: ActivityLabelOverride) async throws {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).save(value)
    }

    public func delete(id: String) async throws {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).delete(id: id)
    }

    public func removeAll() async throws {
        try await ActivityLabelOverrideStore(database: databaseProvider.database()).removeAll()
    }
}
