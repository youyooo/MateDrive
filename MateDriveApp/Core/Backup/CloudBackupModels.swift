import Foundation

public enum CloudBackupKind: String, Codable, Equatable, Sendable {
    case manual
    case automatic
}

public struct CloudBackupDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let createdAt: Date
    public let kind: CloudBackupKind
    public let formatVersion: Int
    public let databaseSchemaVersion: Int
    public let appVersion: String
    public let databaseByteCount: Int64
    public let databaseSHA256: String

    public init(
        id: String,
        createdAt: Date,
        kind: CloudBackupKind,
        formatVersion: Int,
        databaseSchemaVersion: Int,
        appVersion: String,
        databaseByteCount: Int64,
        databaseSHA256: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.formatVersion = formatVersion
        self.databaseSchemaVersion = databaseSchemaVersion
        self.appVersion = appVersion
        self.databaseByteCount = databaseByteCount
        self.databaseSHA256 = databaseSHA256
    }
}

public struct CloudBackupPreferences: Codable, Equatable, Sendable {
    public var hasAcceptedDisclosure: Bool
    public var isAutomaticBackupEnabled: Bool
    public var lastAutomaticBackupAt: Date?
    public var lastSuccessfulBackupAt: Date?
    public var cachedBackups: [CloudBackupDescriptor]

    public init(
        hasAcceptedDisclosure: Bool = false,
        isAutomaticBackupEnabled: Bool = false,
        lastAutomaticBackupAt: Date? = nil,
        lastSuccessfulBackupAt: Date? = nil,
        cachedBackups: [CloudBackupDescriptor] = []
    ) {
        self.hasAcceptedDisclosure = hasAcceptedDisclosure
        self.isAutomaticBackupEnabled = isAutomaticBackupEnabled
        self.lastAutomaticBackupAt = lastAutomaticBackupAt
        self.lastSuccessfulBackupAt = lastSuccessfulBackupAt
        self.cachedBackups = cachedBackups
    }
}

public struct DatabaseBackupArtifact: Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let databaseURL: URL
    public let settingsData: Data
    public let formatVersion: Int
    public let databaseSchemaVersion: Int
    public let appVersion: String
    public let databaseByteCount: Int64
    public let databaseSHA256: String

    public init(
        databaseURL: URL,
        settingsData: Data,
        formatVersion: Int = Self.currentFormatVersion,
        databaseSchemaVersion: Int,
        appVersion: String,
        databaseByteCount: Int64,
        databaseSHA256: String
    ) {
        self.databaseURL = databaseURL
        self.settingsData = settingsData
        self.formatVersion = formatVersion
        self.databaseSchemaVersion = databaseSchemaVersion
        self.appVersion = appVersion
        self.databaseByteCount = databaseByteCount
        self.databaseSHA256 = databaseSHA256
    }
}

public struct DownloadedCloudBackup: Equatable, Sendable {
    public let descriptor: CloudBackupDescriptor
    public let databaseURL: URL
    public let settingsData: Data

    public init(descriptor: CloudBackupDescriptor, databaseURL: URL, settingsData: Data) {
        self.descriptor = descriptor
        self.databaseURL = databaseURL
        self.settingsData = settingsData
    }
}

public struct ValidatedCloudBackup: Equatable, Sendable {
    public let descriptor: CloudBackupDescriptor
    public let databaseURL: URL
    public let settings: AppSettings
}

public enum CloudBackupError: LocalizedError, Equatable, Sendable {
    case disclosureRequired
    case automaticBackupDisabled
    case operationInProgress
    case noICloudAccount
    case iCloudUnavailable
    case quotaExceeded
    case rateLimited(retryAfter: Date?)
    case incompatibleFormat
    case newerDatabaseSchema
    case invalidDatabaseSize
    case invalidChecksum
    case invalidDatabase
    case invalidSettings
    case recordNotFound
    case cancelled
    case serviceFailure(String)
    case restoreFailed(String)
    case rollbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disclosureRequired: return "Cloud backup disclosure must be accepted first."
        case .automaticBackupDisabled: return "Automatic cloud backup is disabled."
        case .operationInProgress: return "Another cloud backup operation is already running."
        case .noICloudAccount: return "No iCloud account is available."
        case .iCloudUnavailable: return "iCloud is temporarily unavailable."
        case .quotaExceeded: return "iCloud storage is full."
        case .rateLimited: return "iCloud requested a later retry."
        case .incompatibleFormat: return "This backup format is not supported."
        case .newerDatabaseSchema: return "This backup was created by a newer MateDrive version."
        case .invalidDatabaseSize: return "The backup file size does not match its metadata."
        case .invalidChecksum: return "The backup checksum is invalid."
        case .invalidDatabase: return "The backup database is damaged."
        case .invalidSettings: return "The backup settings are invalid."
        case .recordNotFound: return "The cloud backup could not be found."
        case .cancelled: return "The cloud backup operation was cancelled."
        case let .serviceFailure(message): return message
        case let .restoreFailed(message): return message
        case let .rollbackFailed(message): return message
        }
    }
}
