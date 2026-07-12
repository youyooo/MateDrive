import Foundation
import SQLite3

public enum SQLiteValue: Sendable {
    case int(Int)
    case double(Double)
    case text(String)
    case null
}

public struct SQLiteCommand: Sendable {
    public let sql: String
    public let bindings: [SQLiteValue]

    public init(_ sql: String, bindings: [SQLiteValue] = []) {
        self.sql = sql
        self.bindings = bindings
    }
}

public enum SQLiteColumnValue: Equatable, Sendable {
    case int(Int)
    case double(Double)
    case text(String)
    case null

    public var intValue: Int? {
        if case let .int(value) = self { value } else { nil }
    }

    public var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        case let .int(value):
            return Double(value)
        case .text, .null:
            return nil
        }
    }

    public var textValue: String? {
        if case let .text(value) = self { value } else { nil }
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    let db: OpaquePointer

    init(db: OpaquePointer) {
        self.db = db
    }

    deinit {
        sqlite3_close(db)
    }
}

public actor SQLiteDatabase {
    private let connection: SQLiteConnection

    private var db: OpaquePointer {
        connection.db
    }

    private init(db: OpaquePointer) {
        self.connection = SQLiteConnection(db: db)
    }

    public static func inMemory() throws -> SQLiteDatabase {
        try open(path: ":memory:")
    }

    public static func open(path: String) throws -> SQLiteDatabase {
        var pointer: OpaquePointer?
        guard sqlite3_open(path, &pointer) == SQLITE_OK, let db = pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
            if let pointer {
                sqlite3_close(pointer)
            }
            throw SQLiteError.openFailed(message)
        }
        return SQLiteDatabase(db: db)
    }

    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw SQLiteError.executionFailed(message)
        }
    }

    public func run(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else {
            throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func performTransaction(_ commands: [SQLiteCommand]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for command in commands {
                try run(command.sql, bindings: command.bindings)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func intValues(_ sql: String, bindings: [SQLiteValue] = []) throws -> [Int] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        var values: [Int] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return values
            }
            guard status == SQLITE_ROW else {
                throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            values.append(Int(sqlite3_column_int64(statement, 0)))
        }
    }

    public func textValues(_ sql: String, bindings: [SQLiteValue] = []) throws -> [String] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        var values: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return values
            }
            guard status == SQLITE_ROW else {
                throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            if let text = sqlite3_column_text(statement, 0) {
                let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
                values.append(String(cString: cString))
            }
        }
    }

    public func rows(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[SQLiteColumnValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        var rows: [[SQLiteColumnValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return rows
            }
            guard status == SQLITE_ROW else {
                throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            let columnCount = sqlite3_column_count(statement)
            let row = (0..<columnCount).map { index in
                columnValue(statement: statement, index: index)
            }
            rows.append(row)
        }
    }

    public func tableNames() throws -> Set<String> {
        let names = try textValues(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
            ORDER BY name;
            """
        )
        return Set(names)
    }

    public func userVersion() throws -> Int {
        guard let version = try intValues("PRAGMA user_version;").first else {
            throw SQLiteError.noRows
        }
        return version
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .int(let int):
                status = sqlite3_bind_int64(statement, position, sqlite3_int64(int))
            case .double(let double):
                status = sqlite3_bind_double(statement, position, double)
            case .text(let string):
                status = sqlite3_bind_text(statement, position, string, -1, SQLITE_TRANSIENT)
            case .null:
                status = sqlite3_bind_null(statement, position)
            }
            guard status == SQLITE_OK else {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func columnValue(statement: OpaquePointer, index: Int32) -> SQLiteColumnValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else {
                return .null
            }
            let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
            return .text(String(cString: cString))
        default:
            return .null
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
