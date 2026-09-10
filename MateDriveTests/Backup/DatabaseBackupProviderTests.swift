import CryptoKit
import XCTest
@testable import MateDriveApp

final class DatabaseBackupProviderTests: XCTestCase {
    func testArtifactContainsConsistentDatabaseAndSanitizedSettings() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase.open(path: directory.appendingPathComponent("live.sqlite").path)
        try await Migrations.applyAll(to: database)
        try await database.run(
            "INSERT INTO sync_state (key, value, updated_at) VALUES ('cursor', '42', 'now');"
        )
        let label = Self.labelFixture
        let observation = Self.pricingObservationFixture
        try await SmartActivityStore(database: database).replace(
            carId: 1,
            sessions: [Self.sessionFixture],
            derivationFingerprint: "backup-fingerprint"
        )
        try await ActivityLabelOverrideStore(database: database).save(label)
        try await ChargePricingObservationStore(database: database).save(observation)
        var settings = AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY",
            lastSelectedCarId: 7
        )
        settings.homeTariffRegionCode = "CN-43"
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
        let restoredSession = try await SmartActivityStore(database: snapshot).session(
            carId: 1,
            sessionId: Self.sessionFixture.id
        )
        let restoredLabel = try await ActivityLabelOverrideStore(database: snapshot).override(id: label.id)
        let restoredObservations = try await ChargePricingObservationStore(database: snapshot).observations(
            carId: observation.carId,
            stationKey: observation.stationKey
        )
        let restoredSettings = try JSONDecoder().decode(AppSettings.self, from: artifact.settingsData)
        XCTAssertEqual(cursor, ["42"])
        XCTAssertEqual(restoredSession, Self.sessionFixture)
        XCTAssertEqual(restoredLabel, label)
        XCTAssertEqual(restoredObservations, [observation])
        XCTAssertEqual(restoredSettings, settings)
        XCTAssertEqual(restoredSettings.homeTariffRegionCode, "CN-43")
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

    func testSettingsPayloadDropsLegacyURLsContainingEmbeddedSecrets() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase.open(path: directory.appendingPathComponent("live.sqlite").path)
        try await Migrations.applyAll(to: database)
        let provider = DatabaseBackupProvider(
            databaseProvider: BackupDatabaseProvider(database: database),
            settingsStore: BackupSettingsStore(settings: AppSettings(
                serverURL: "https://alice" + ":secret-password@example.com",
                secondaryServerURL: "https://backup.example?token=secret-token",
                currencyCode: "CNY",
                teslamateBaseURL: "https://grafana.example#secret-fragment"
            )),
            temporaryDirectory: { directory.appendingPathComponent("artifacts", isDirectory: true) }
        )

        let artifact = try await provider.createArtifact(appVersion: "1.0")
        defer { provider.removeArtifact(at: artifact.databaseURL) }
        let payload = String(decoding: artifact.settingsData, as: UTF8.self)
        let settings = try JSONDecoder().decode(AppSettings.self, from: artifact.settingsData)

        XCTAssertEqual(settings.serverURL, "")
        XCTAssertEqual(settings.secondaryServerURL, "")
        XCTAssertEqual(settings.teslamateBaseURL, "")
        XCTAssertEqual(settings.currencyCode, "CNY")
        for secret in ["alice", "secret-password", "secret-token", "secret-fragment"] {
            XCTAssertFalse(payload.contains(secret))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseBackupProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let sessionFixture = SmartActivitySession(
        id: "backup-session",
        carId: 1,
        startDate: Date(timeIntervalSince1970: 1_720_000_000),
        endDate: Date(timeIntervalSince1970: 1_720_003_600),
        placeKey: "station",
        latitude: SyntheticCoordinates.point(latitudeOffset: 0.23).northing,
        longitude: SyntheticCoordinates.point(longitudeOffset: 0.93).easting,
        geofenceID: nil,
        provisionalKind: .replenishment,
        classification: nil,
        parkingMetrics: nil,
        chargeCost: nil,
        eventReferences: [],
        isOpen: false,
        quality: .complete,
        derivationVersion: 1,
        sourceFingerprint: "backup-source",
        derivationFingerprint: "backup-fingerprint"
    )

    private static let labelFixture = ActivityLabelOverride(
        id: "backup-label",
        carId: 1,
        sessionId: nil,
        placeKey: "station",
        scope: .futureAtPlace,
        purpose: .replenishment,
        customName: "Night charging",
        icon: "bolt.fill",
        colorHex: "#34C759",
        startMinute: 1_380,
        endMinute: 360,
        updatedAt: Date(timeIntervalSince1970: 1_720_003_700)
    )

    private static let pricingObservationFixture = ChargePricingObservation(
        id: "backup-price",
        carId: 1,
        chargeId: 88,
        stationKey: "station",
        scope: .futureAtStation,
        finalAmount: 13.2,
        billedEnergyKWh: 20,
        pricePerKWh: 0.66,
        serviceFeePerKWh: nil,
        fixedFee: nil,
        currencyCode: "CNY",
        confirmedAt: Date(timeIntervalSince1970: 1_720_003_800)
    )
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
