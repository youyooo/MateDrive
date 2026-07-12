import Foundation

public protocol TeslaMateServerProfileStoring: Sendable {
    func profile(serverKey: String, carId: Int) async throws -> TeslaMateServerProfile?
    func save(_ profile: TeslaMateServerProfile) async throws
    func delete(serverKey: String) async throws
}

public struct EmptyTeslaMateServerProfileStore: TeslaMateServerProfileStoring {
    public init() {}

    public func profile(serverKey _: String, carId _: Int) async throws -> TeslaMateServerProfile? {
        nil
    }

    public func save(_: TeslaMateServerProfile) async throws {}

    public func delete(serverKey _: String) async throws {}
}

public struct DatabaseBackedTeslaMateServerProfileStore: TeslaMateServerProfileStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func profile(serverKey: String, carId: Int) async throws -> TeslaMateServerProfile? {
        let database = try await databaseProvider.database()
        return try await TeslaMateServerProfileStore(database: database)
            .profile(serverKey: serverKey, carId: carId)
    }

    public func save(_ profile: TeslaMateServerProfile) async throws {
        let database = try await databaseProvider.database()
        try await TeslaMateServerProfileStore(database: database).save(profile)
    }

    public func delete(serverKey: String) async throws {
        let database = try await databaseProvider.database()
        try await TeslaMateServerProfileStore(database: database).delete(serverKey: serverKey)
    }
}

public struct TeslaMateServerProfileStore: TeslaMateServerProfileStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func profile(serverKey: String, carId: Int) async throws -> TeslaMateServerProfile? {
        let rows = try await database.rows(
            """
            SELECT capability, status_json, connection_issue_json, api_version, mt_api_version, build_info,
                   checked_at, last_successful_check_at
            FROM teslamate_capabilities
            WHERE server_key = ? AND car_id = ?
            ORDER BY capability;
            """,
            bindings: [.text(serverKey), .int(carId)]
        )
        guard let first = rows.first else {
            return nil
        }
        guard first.count == 8,
              let checkedText = first[6].textValue,
              let checkedAt = ISO8601DateFormatter().date(from: checkedText)
        else {
            throw SQLiteError.executionFailed("Invalid TeslaMate capability profile metadata")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var capabilities: [TeslaMateCapability: TeslaMateCapabilityStatus] = [:]
        for row in rows {
            guard row.count == 8,
                  let capabilityText = row[0].textValue,
                  let statusText = row[1].textValue,
                  let statusData = statusText.data(using: .utf8)
            else {
                throw SQLiteError.executionFailed("Invalid TeslaMate capability row")
            }
            guard let capability = TeslaMateCapability(rawValue: capabilityText) else {
                continue
            }
            capabilities[capability] = try decoder.decode(TeslaMateCapabilityStatus.self, from: statusData)
        }

        let connectionIssue = try first[2].textValue.map { text in
            try decoder.decode(TeslaMateConnectionIssue.self, from: Data(text.utf8))
        }
        let formatter = ISO8601DateFormatter()
        return TeslaMateServerProfile(
            serverKey: serverKey,
            carId: carId,
            version: TeslaMateVersionInfo(
                apiVersion: first[3].textValue,
                mtAPIVersion: first[4].textValue,
                buildInfo: first[5].textValue
            ),
            capabilities: capabilities,
            connectionIssue: connectionIssue,
            checkedAt: checkedAt,
            lastSuccessfulCheckAt: first[7].textValue.flatMap(formatter.date(from:))
        )
    }

    public func save(_ profile: TeslaMateServerProfile) async throws {
        guard !profile.capabilities.isEmpty else {
            throw SQLiteError.executionFailed("TeslaMate capability profile has no capabilities")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let formatter = ISO8601DateFormatter()
        let connectionIssueJSON = try profile.connectionIssue.map {
            String(decoding: try encoder.encode($0), as: UTF8.self)
        }
        var commands = [
            SQLiteCommand(
                "DELETE FROM teslamate_capabilities WHERE server_key = ? AND car_id = ?;",
                bindings: [.text(profile.serverKey), .int(profile.carId)]
            )
        ]

        for capability in profile.capabilities.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let status = profile.capabilities[capability] else {
                continue
            }
            let statusJSON = String(decoding: try encoder.encode(status), as: UTF8.self)
            commands.append(SQLiteCommand(
                """
                INSERT INTO teslamate_capabilities
                (server_key, car_id, capability, status_json, connection_issue_json, api_version, mt_api_version,
                 build_info, checked_at, last_successful_check_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(profile.serverKey),
                    .int(profile.carId),
                    .text(capability.rawValue),
                    .text(statusJSON),
                    connectionIssueJSON.map(SQLiteValue.text) ?? .null,
                    profile.version.apiVersion.map(SQLiteValue.text) ?? .null,
                    profile.version.mtAPIVersion.map(SQLiteValue.text) ?? .null,
                    profile.version.buildInfo.map(SQLiteValue.text) ?? .null,
                    .text(formatter.string(from: profile.checkedAt)),
                    profile.lastSuccessfulCheckAt.map { .text(formatter.string(from: $0)) } ?? .null
                ]
            ))
        }
        try await database.performTransaction(commands)
    }

    public func delete(serverKey: String) async throws {
        try await database.run(
            "DELETE FROM teslamate_capabilities WHERE server_key = ?;",
            bindings: [.text(serverKey)]
        )
    }
}
