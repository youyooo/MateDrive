import Foundation

public enum SQLiteError: LocalizedError, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case executionFailed(String)
    case noRows

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "SQLite open failed: \(message)"
        case let .prepareFailed(message):
            return "SQLite prepare failed: \(message)"
        case let .bindFailed(message):
            return "SQLite bind failed: \(message)"
        case let .executionFailed(message):
            return "SQLite execution failed: \(message)"
        case .noRows:
            return "SQLite returned no rows."
        }
    }
}
