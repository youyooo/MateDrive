import CryptoKit
import Foundation

public protocol DatabaseBackupProviding: Sendable {
    func createArtifact(appVersion: String) async throws -> DatabaseBackupArtifact
    func validate(_ backup: DownloadedCloudBackup) async throws -> ValidatedCloudBackup
    func restoreDatabase(from url: URL) async throws
    func migrateRestoredDatabase() async throws
    func restoreSettings(_ settings: AppSettings) async
    func currentSettings() async -> AppSettings
    func removeArtifact(at url: URL)
}

public extension DatabaseBackupProviding {
    func migrateRestoredDatabase() async throws {}
}

public struct DatabaseBackupProvider: DatabaseBackupProviding, Sendable {
    private let databaseProvider: any AppDatabaseProviding
    private let settingsStore: any SettingsStoring
    private let temporaryDirectory: @Sendable () -> URL

    public init(
        databaseProvider: any AppDatabaseProviding,
        settingsStore: any SettingsStoring,
        temporaryDirectory: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory.appendingPathComponent("MateDriveCloudBackup", isDirectory: true)
        }
    ) {
        self.databaseProvider = databaseProvider
        self.settingsStore = settingsStore
        self.temporaryDirectory = temporaryDirectory
    }

    public func createArtifact(appVersion: String) async throws -> DatabaseBackupArtifact {
        let artifactDirectory = temporaryDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: artifactDirectory.path
        )
        let databaseURL = artifactDirectory.appendingPathComponent("matedrive.sqlite")

        do {
            let database = try await databaseProvider.database()
            let metadata = try await database.backup(to: databaseURL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let settingsData = try encoder.encode(await settingsStore.load())
            return DatabaseBackupArtifact(
                databaseURL: databaseURL,
                settingsData: settingsData,
                databaseSchemaVersion: metadata.schemaVersion,
                appVersion: appVersion,
                databaseByteCount: metadata.byteCount,
                databaseSHA256: try Self.sha256(of: databaseURL)
            )
        } catch {
            try? fileManager.removeItem(at: artifactDirectory)
            throw error
        }
    }

    public func validate(_ backup: DownloadedCloudBackup) async throws -> ValidatedCloudBackup {
        let fileManager = FileManager.default
        guard backup.descriptor.formatVersion <= DatabaseBackupArtifact.currentFormatVersion else {
            throw CloudBackupError.incompatibleFormat
        }
        guard backup.descriptor.databaseSchemaVersion <= DatabaseSchemaVersion.current else {
            throw CloudBackupError.newerDatabaseSchema
        }
        let attributes = try fileManager.attributesOfItem(atPath: backup.databaseURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard byteCount == backup.descriptor.databaseByteCount else {
            throw CloudBackupError.invalidDatabaseSize
        }
        guard try Self.sha256(of: backup.databaseURL) == backup.descriptor.databaseSHA256 else {
            throw CloudBackupError.invalidChecksum
        }

        do {
            let snapshot = try SQLiteDatabase.open(path: backup.databaseURL.path)
            guard try await snapshot.integrityCheck(),
                  try await snapshot.schemaVersion() == backup.descriptor.databaseSchemaVersion
            else { throw CloudBackupError.invalidDatabase }
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw CloudBackupError.invalidDatabase
        }

        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: backup.settingsData) else {
            throw CloudBackupError.invalidSettings
        }
        return ValidatedCloudBackup(
            descriptor: backup.descriptor,
            databaseURL: backup.databaseURL,
            settings: settings
        )
    }

    public func restoreDatabase(from url: URL) async throws {
        let database = try await databaseProvider.database()
        try await database.restore(from: url)
    }

    public func migrateRestoredDatabase() async throws {
        let database = try await databaseProvider.database()
        try await Migrations.applyAll(to: database)
    }

    public func restoreSettings(_ settings: AppSettings) async {
        await settingsStore.save(settings)
    }

    public func currentSettings() async -> AppSettings {
        await settingsStore.load()
    }

    public func removeArtifact(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        let parent = url.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
