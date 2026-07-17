import Foundation

public struct Migration: Sendable {
    public let version: Int
    public let statements: [String]

    public init(version: Int, statements: [String]) {
        self.version = version
        self.statements = statements
    }
}

public enum SchemaVersion {
    public static let current = 13
}

public enum DatabaseSchemaVersion {
    public static let current = 20
}
