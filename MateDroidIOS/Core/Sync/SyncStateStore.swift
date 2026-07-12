import Foundation

public struct SyncStateRecord: Codable, Equatable, Sendable {
    public let carId: Int
    public var lastDriveSyncAt: Int64
    public var lastChargeSyncAt: Int64
    public var lastDriveDetailId: Int
    public var lastChargeDetailId: Int
    public var detailSchemaVersion: Int
    public var totalDrivesToProcess: Int
    public var totalChargesToProcess: Int
    public var drivesProcessed: Int
    public var chargesProcessed: Int
    public var summariesSynced: Bool
    public var detailsSynced: Bool

    public init(
        carId: Int,
        lastDriveSyncAt: Int64 = 0,
        lastChargeSyncAt: Int64 = 0,
        lastDriveDetailId: Int = 0,
        lastChargeDetailId: Int = 0,
        detailSchemaVersion: Int = SchemaVersion.current,
        totalDrivesToProcess: Int = 0,
        totalChargesToProcess: Int = 0,
        drivesProcessed: Int = 0,
        chargesProcessed: Int = 0,
        summariesSynced: Bool = false,
        detailsSynced: Bool = false
    ) {
        self.carId = carId
        self.lastDriveSyncAt = lastDriveSyncAt
        self.lastChargeSyncAt = lastChargeSyncAt
        self.lastDriveDetailId = lastDriveDetailId
        self.lastChargeDetailId = lastChargeDetailId
        self.detailSchemaVersion = detailSchemaVersion
        self.totalDrivesToProcess = totalDrivesToProcess
        self.totalChargesToProcess = totalChargesToProcess
        self.drivesProcessed = drivesProcessed
        self.chargesProcessed = chargesProcessed
        self.summariesSynced = summariesSynced
        self.detailsSynced = detailsSynced
    }
}

public protocol SyncStateStoring: Sendable {
    func state(carId: Int) async throws -> SyncStateRecord?
    func upsertState(_ state: SyncStateRecord) async throws
}

public struct HistorySyncHealth: Equatable, Sendable {
    public let driveSummaryCount: Int
    public let driveDetailCount: Int
    public let pendingDriveCount: Int
    public let chargeSummaryCount: Int
    public let chargeDetailCount: Int
    public let pendingChargeCount: Int
    public let lastSyncAtMilliseconds: Int64?

    public var isComplete: Bool {
        pendingDriveCount == 0 && pendingChargeCount == 0 &&
            driveSummaryCount == driveDetailCount && chargeSummaryCount == chargeDetailCount
    }

    public init(
        driveSummaryCount: Int,
        driveDetailCount: Int,
        pendingDriveCount: Int,
        chargeSummaryCount: Int,
        chargeDetailCount: Int,
        pendingChargeCount: Int,
        lastSyncAtMilliseconds: Int64?
    ) {
        self.driveSummaryCount = driveSummaryCount
        self.driveDetailCount = driveDetailCount
        self.pendingDriveCount = pendingDriveCount
        self.chargeSummaryCount = chargeSummaryCount
        self.chargeDetailCount = chargeDetailCount
        self.pendingChargeCount = pendingChargeCount
        self.lastSyncAtMilliseconds = lastSyncAtMilliseconds
    }
}

public protocol HistorySyncHealthProviding: Sendable {
    func health(carId: Int?) async throws -> HistorySyncHealth
}

public struct EmptyHistorySyncHealthProvider: HistorySyncHealthProviding {
    public init() {}

    public func health(carId _: Int?) async throws -> HistorySyncHealth {
        HistorySyncHealth(
            driveSummaryCount: 0,
            driveDetailCount: 0,
            pendingDriveCount: 0,
            chargeSummaryCount: 0,
            chargeDetailCount: 0,
            pendingChargeCount: 0,
            lastSyncAtMilliseconds: nil
        )
    }
}

public struct DatabaseBackedHistorySyncHealthProvider: HistorySyncHealthProviding {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func health(carId: Int?) async throws -> HistorySyncHealth {
        let database = try await databaseProvider.database()
        let summaryFilter = carId == nil ? "" : " WHERE car_id = ?"
        let detailFilter = carId == nil ? " WHERE schema_version = ?" : " WHERE schema_version = ? AND car_id = ?"
        let summaryBindings = carId.map { [SQLiteValue.int($0)] } ?? []
        let detailBindings: [SQLiteValue] = [.int(SchemaVersion.current)] + (carId.map { [.int($0)] } ?? [])
        let joinCarFilter = carId == nil ? "" : " AND summary.car_id = ?"
        let pendingBindings: [SQLiteValue] = [.int(SchemaVersion.current), .int(SchemaVersion.current)] + (carId.map { [.int($0)] } ?? [])

        let driveSummaries = try await count(database, "SELECT COUNT(*) FROM drives_summary\(summaryFilter);", summaryBindings)
        let driveDetails = try await count(database, "SELECT COUNT(*) FROM drive_detail_aggregates\(detailFilter);", detailBindings)
        let pendingDrives = try await count(
            database,
            """
            SELECT COUNT(*) FROM drives_summary AS summary
            LEFT JOIN drive_detail_aggregates AS detail
              ON detail.drive_id = summary.drive_id AND detail.schema_version = ?
            WHERE (summary.schema_version != ? OR detail.drive_id IS NULL)\(joinCarFilter);
            """,
            pendingBindings
        )
        let chargeSummaries = try await count(database, "SELECT COUNT(*) FROM charges_summary\(summaryFilter);", summaryBindings)
        let chargeDetails = try await count(database, "SELECT COUNT(*) FROM charge_detail_aggregates\(detailFilter);", detailBindings)
        let pendingCharges = try await count(
            database,
            """
            SELECT COUNT(*) FROM charges_summary AS summary
            LEFT JOIN charge_detail_aggregates AS detail
              ON detail.charge_id = summary.charge_id AND detail.schema_version = ?
            WHERE (summary.schema_version != ? OR detail.charge_id IS NULL)\(joinCarFilter);
            """,
            pendingBindings
        )
        let states = try await syncStates(database: database, carId: carId)
        let lastSync = states.map { max($0.lastDriveSyncAt, $0.lastChargeSyncAt) }.filter { $0 > 0 }.max()
        return HistorySyncHealth(
            driveSummaryCount: driveSummaries,
            driveDetailCount: driveDetails,
            pendingDriveCount: pendingDrives,
            chargeSummaryCount: chargeSummaries,
            chargeDetailCount: chargeDetails,
            pendingChargeCount: pendingCharges,
            lastSyncAtMilliseconds: lastSync
        )
    }

    private func count(_ database: SQLiteDatabase, _ sql: String, _ bindings: [SQLiteValue]) async throws -> Int {
        try await database.intValues(sql, bindings: bindings).first ?? 0
    }

    private func syncStates(database: SQLiteDatabase, carId: Int?) async throws -> [SyncStateRecord] {
        let values: [String]
        if let carId {
            values = try await database.textValues(
                "SELECT value FROM sync_state WHERE key = ?;",
                bindings: [.text("car:\(carId)")]
            )
        } else {
            values = try await database.textValues("SELECT value FROM sync_state WHERE key LIKE 'car:%';")
        }
        let decoder = JSONDecoder()
        return values.compactMap { try? decoder.decode(SyncStateRecord.self, from: Data($0.utf8)) }
    }
}

public struct SQLiteSyncStateStore: SyncStateStoring {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func state(carId: Int) async throws -> SyncStateRecord? {
        let values = try await database.textValues(
            "SELECT value FROM sync_state WHERE key = ? LIMIT 1;",
            bindings: [.text(key(carId: carId))]
        )
        guard let value = values.first, let data = value.data(using: .utf8) else {
            return nil
        }
        return try decoder.decode(SyncStateRecord.self, from: data)
    }

    public func upsertState(_ state: SyncStateRecord) async throws {
        let data = try encoder.encode(state)
        let value = String(decoding: data, as: UTF8.self)
        try await database.run(
            """
            INSERT OR REPLACE INTO sync_state (key, value, updated_at)
            VALUES (?, ?, ?);
            """,
            bindings: [.text(key(carId: state.carId)), .text(value), .text(Date().ISO8601Format())]
        )
    }

    private func key(carId: Int) -> String {
        "car:\(carId)"
    }
}
