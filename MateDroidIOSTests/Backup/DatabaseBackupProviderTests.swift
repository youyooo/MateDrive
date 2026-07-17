import CryptoKit
import XCTest
@testable import MateDroidIOS

final class DatabaseBackupProviderTests: XCTestCase {
    func testArtifactContainsConsistentDatabaseAndSanitizedSettings() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase.open(path: directory.appendingPathComponent("live.sqlite").path)
        try await Migrations.applyAll(to: database)
        try await database.run(
            "INSERT INTO sync_state (key, value, updated_at) VALUES ('cursor', '42', 'now');"
        )
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY",
            lastSelectedCarId: 7
        )
        let settingsStore = BackupSettingsStore(settings: settings)
        let provider = DatabaseBackupProvider(
            databaseProvider: BackupDatabaseProvider(database: database),
            settingsStore: settingsStore,
            temporaryDirectory: { directory.appendingPathComponent("artifacts", isDirectory: true) }
        )

        let artifact = try await provider.createArtifact(appVersion: "1.2.3")
        defer { provider.removeArtifact(at: artifact.databaseURL) }

        let snapshot = try SQLiteDatabase.open(path: artifact.databaseURL.path)
        let cursor = try await snapshot.textValues("SELECT value FROM sync_state WHERE key = 'cursor';")
        let restoredSettings = try JSONDecoder().decode(AppSettings.self, from: artifact.settingsData)
        XCTAssertEqual(cursor, ["42"])
        XCTAssertEqual(restoredSettings, settings)
        XCTAssertEqual(artifact.databaseSchemaVersion, DatabaseSchemaVersion.current)
        XCTAssertEqual(artifact.appVersion, "1.2.3")
        XCTAssertEqual(artifact.databaseSHA256, try DatabaseBackupProvider.sha256(of: artifact.databaseURL))
        XCTAssertGreaterThan(artifact.databaseByteCount, 0)
    }

    func testValidationRejectsTamperedDatabaseBeforeRestore() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase.open(path: directory.appendingPathComponent("live.sqlite").path)
        try await Migrations.applyAll(to: database)
        let settingsStore = BackupSettingsStore(settings: AppSettings())
        let provider = DatabaseBackupProvider(
            databaseProvider: BackupDatabaseProvider(database: database),
            settingsStore: settingsStore,
            temporaryDirectory: { directory.appendingPathComponent("artifacts", isDirectory: true) }
        )
        let artifact = try await provider.createArtifact(appVersion: "1.0")
        defer { provider.removeArtifact(at: artifact.databaseURL) }
        let descriptor = CloudBackupDescriptor(
            id: "backup-1",
            createdAt: Date(),
            kind: .manual,
            formatVersion: artifact.formatVersion,
            databaseSchemaVersion: artifact.databaseSchemaVersion,
            appVersion: artifact.appVersion,
            databaseByteCount: artifact.databaseByteCount,
            databaseSHA256: artifact.databaseSHA256
        )
        let handle = try FileHandle(forWritingTo: artifact.databaseURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()

        do {
            _ = try await provider.validate(
                DownloadedCloudBackup(
                    descriptor: descriptor,
                    databaseURL: artifact.databaseURL,
                    settingsData: artifact.settingsData
                )
            )
            XCTFail("Expected checksum validation to fail")
        } catch let error as CloudBackupError {
            XCTAssertEqual(error, .invalidDatabaseSize)
        }
    }

    func testSettingsPayloadDoesNotContainExternalAuthenticationSecrets() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase.open(path: directory.appendingPathComponent("live.sqlite").path)
        try await Migrations.applyAll(to: database)
        let provider = DatabaseBackupProvider(
            databaseProvider: BackupDatabaseProvider(database: database),
            settingsStore: BackupSettingsStore(settings: AppSettings(serverURL: "https://example.com")),
            temporaryDirectory: { directory.appendingPathComponent("artifacts", isDirectory: true) }
        )

        let artifact = try await provider.createArtifact(appVersion: "1.0")
        defer { provider.removeArtifact(at: artifact.databaseURL) }
        let payload = String(decoding: artifact.settingsData, as: UTF8.self)

        XCTAssertFalse(payload.contains("secret-password"))
        XCTAssertFalse(payload.contains("secret-token"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseBackupProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor BackupSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}

private struct BackupDatabaseProvider: AppDatabaseProviding {
    let databaseValue: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.databaseValue = database
    }

    func database() async throws -> SQLiteDatabase { databaseValue }
}
