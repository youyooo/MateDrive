import Foundation

public protocol SleepIntervalStoring: Sendable {
    func upsertAll(_ records: [SleepIntervalRecord]) async throws
    func records(carId: Int, start: String, end: String) async throws -> [SleepIntervalRecord]
}

public struct SleepIntervalStore: SleepIntervalStoring {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsertAll(_ records: [SleepIntervalRecord]) async throws {
        guard !records.isEmpty else { return }
        let commands = records.map { record in
            SQLiteCommand(
                """
                INSERT INTO sleep_intervals (car_id, start_date, end_date)
                VALUES (?, ?, ?)
                ON CONFLICT(car_id, start_date, end_date) DO NOTHING;
                """,
                bindings: [.int(record.carId), .text(record.startDate), .text(record.endDate)]
            )
        }
        try await database.performTransaction(commands)
    }

    public func records(carId: Int, start: String, end: String) async throws -> [SleepIntervalRecord] {
        let rows = try await database.rows(
            """
            SELECT car_id, start_date, end_date
            FROM sleep_intervals
            WHERE car_id = ?
              AND start_date < ?
              AND end_date > ?
            ORDER BY start_date ASC;
            """,
            bindings: [.int(carId), .text(end), .text(start)]
        )
        return rows.compactMap { row in
            guard row.count == 3,
                  let rowCarId = row[0].intValue,
                  let startDate = row[1].textValue,
                  let endDate = row[2].textValue
            else {
                return nil
            }
            return SleepIntervalRecord(carId: rowCarId, startDate: startDate, endDate: endDate)
        }
    }
}

public struct DatabaseBackedSleepIntervalStore: SleepIntervalStoring {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func upsertAll(_ records: [SleepIntervalRecord]) async throws {
        let database = try await databaseProvider.database()
        try await SleepIntervalStore(database: database).upsertAll(records)
    }

    public func records(carId: Int, start: String, end: String) async throws -> [SleepIntervalRecord] {
        let database = try await databaseProvider.database()
        return try await SleepIntervalStore(database: database).records(
            carId: carId,
            start: start,
            end: end
        )
    }
}
