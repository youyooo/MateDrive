import Foundation

public struct Migration: Sendable {
    public let version: Int
    public let statements: [String]
    public let columnsToAddIfMissing: [MigrationColumn]

    public init(
        version: Int,
        statements: [String],
        columnsToAddIfMissing: [MigrationColumn] = []
    ) {
        self.version = version
        self.statements = statements
        self.columnsToAddIfMissing = columnsToAddIfMissing
    }
}

public struct MigrationColumn: Sendable {
    public let table: String
    public let name: String
    public let definition: String

    public init(table: String, name: String, definition: String) {
        self.table = table
        self.name = name
        self.definition = definition
    }
}

public enum SchemaVersion {
    public static let current = 13
}

public enum DatabaseSchemaVersion {
    public static let current = 23
}
