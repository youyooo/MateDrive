import Foundation
import XCTest
@testable import MateDroidIOS

final class CloudBackupRestoreTests: XCTestCase {
    func testRestoreValidatesThenReplacesMigratesInvalidatesAndResumesSync() async throws {
        let fixture = makeFixture()

        try await fixture.coordinator.restore(fixture.descriptor)

        let syncEvents = await fixture.sync.events
        let databaseState = fixture.database.state()
        let invalidationCount = await fixture.invalidator.callCount
        let reloadCount = await fixture.reloader.callCount
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
        XCTAssertEqual(databaseState.restoredURLs, [fixture.downloadURL])
        XCTAssertEqual(databaseState.migrationCount, 1)
        XCTAssertEqual(databaseState.settings.serverURL, "https://restored.example")
        XCTAssertEqual(invalidationCount, 1)
        XCTAssertEqual(reloadCount, 1)
        XCTAssertTrue(databaseState.removedURLs.contains(fixture.downloadURL))
        XCTAssertTrue(databaseState.removedURLs.contains(fixture.safetyURL))
    }

    func testValidationFailureNeverCreatesSafetySnapshotOrChangesLocalData() async {
        let fixture = makeFixture()
        fixture.database.setValidationError(CloudBackupError.invalidChecksum)

        do {
            try await fixture.coordinator.restore(fixture.descriptor)
            XCTFail("Expected validation failure")
        } catch let error as CloudBackupError {
            XCTAssertEqual(error, .invalidChecksum)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = fixture.database.state()
        let syncEvents = await fixture.sync.events
        XCTAssertEqual(state.artifactCount, 0)
        XCTAssertTrue(state.restoredURLs.isEmpty)
        XCTAssertEqual(state.settings.serverURL, "https://original.example")
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    func testFailureAfterReplacementRollsBackDatabaseAndSettingsBeforeResuming() async {
        let fixture = makeFixture()
        await fixture.reloader.failNext(with: RestoreTestError.reloadFailed)

        do {
            try await fixture.coordinator.restore(fixture.descriptor)
            XCTFail("Expected restore failure")
        } catch let error as CloudBackupError {
            guard case .restoreFailed = error else {
                return XCTFail("Unexpected cloud error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let state = fixture.database.state()
        let syncEvents = await fixture.sync.events
        let invalidationCount = await fixture.invalidator.callCount
        XCTAssertEqual(state.restoredURLs, [fixture.downloadURL, fixture.safetyURL])
        XCTAssertEqual(state.migrationCount, 2)
        XCTAssertEqual(state.settings.serverURL, "https://original.example")
        XCTAssertEqual(invalidationCount, 2)
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    func testRollbackFailureIsReportedAndSyncStillResumes() async {
        let fixture = makeFixture()
        await fixture.reloader.failNext(with: RestoreTestError.reloadFailed)
        fixture.database.setRestoreError(RestoreTestError.rollbackFailed, call: 2)

        do {
            try await fixture.coordinator.restore(fixture.descriptor)
            XCTFail("Expected rollback failure")
        } catch let error as CloudBackupError {
            guard case .rollbackFailed = error else {
                return XCTFail("Unexpected cloud error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let syncEvents = await fixture.sync.events
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    private func makeFixture() -> RestoreFixture {
        let descriptor = CloudBackupDescriptor(
            id: "backup-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .manual,
            formatVersion: 1,
            databaseSchemaVersion: DatabaseSchemaVersion.current,
            appVersion: "1.0",
            databaseByteCount: 100,
            databaseSHA256: "hash"
        )
        let downloadURL = URL(fileURLWithPath: "/tmp/cloud-backup.sqlite")
        let safetyURL = URL(fileURLWithPath: "/tmp/safety-backup.sqlite")
        let service = RestoreCloudBackupService(download: DownloadedCloudBackup(
            descriptor: descriptor,
            databaseURL: downloadURL,
            settingsData: Data("{}".utf8)
        ))
        let database = RestoreDatabaseBackupProvider(
            safetyURL: safetyURL,
            originalSettings: AppSettings(serverURL: "https://original.example"),
            restoredSettings: AppSettings(serverURL: "https://restored.example")
        )
        let sync = RestoreSyncSuspender()
        let invalidator = RestoreCacheInvalidator()
        let reloader = RestoreReloadObserver()
        let coordinator = CloudBackupCoordinator(
            service: service,
            databaseProvider: database,
            preferencesStore: RestorePreferencesStore(),
            syncController: sync,
            cacheInvalidator: invalidator,
            appVersion: { "1.0" },
            didRestore: { try await reloader.reload() }
        )
        return RestoreFixture(
            coordinator: coordinator,
            descriptor: descriptor,
            database: database,
            sync: sync,
            invalidator: invalidator,
            reloader: reloader,
            downloadURL: downloadURL,
            safetyURL: safetyURL
        )
    }
}

private struct RestoreFixture {
    let coordinator: CloudBackupCoordinator
    let descriptor: CloudBackupDescriptor
    let database: RestoreDatabaseBackupProvider
    let sync: RestoreSyncSuspender
    let invalidator: RestoreCacheInvalidator
    let reloader: RestoreReloadObserver
    let downloadURL: URL
    let safetyURL: URL
}

private enum RestoreTestError: Error {
    case reloadFailed
    case rollbackFailed
}

private actor RestoreCloudBackupService: CloudBackupServicing {
    let download: DownloadedCloudBackup
    init(download: DownloadedCloudBackup) { self.download = download }
    func accountStatus() async throws -> CloudBackupAccountStatus { .available }
    func listBackups() async throws -> [CloudBackupDescriptor] { [download.descriptor] }
    func upload(_: DatabaseBackupArtifact, kind _: CloudBackupKind) async throws -> CloudBackupDescriptor {
        download.descriptor
    }
    func download(_: CloudBackupDescriptor) async throws -> DownloadedCloudBackup { download }
    func delete(_: CloudBackupDescriptor) async throws {}
    func deleteAll() async throws {}
}

private actor RestorePreferencesStore: CloudBackupPreferencesStoring {
    private var value = CloudBackupPreferences()
    func load() -> CloudBackupPreferences { value }
    func save(_ preferences: CloudBackupPreferences) { value = preferences }
}

private final class RestoreDatabaseBackupProvider: DatabaseBackupProviding, @unchecked Sendable {
    struct State {
        let artifactCount: Int
        let restoredURLs: [URL]
        let migrationCount: Int
        let settings: AppSettings
        let removedURLs: [URL]
    }

    private let lock = NSLock()
    private let safetyURL: URL
    private let restoredSettings: AppSettings
    private var settings: AppSettings
    private var validationError: Error?
    private var restoreErrors: [Int: Error] = [:]
    private var artifactCount = 0
    private var restoredURLs: [URL] = []
    private var migrationCount = 0
    private var removedURLs: [URL] = []

    init(safetyURL: URL, originalSettings: AppSettings, restoredSettings: AppSettings) {
        self.safetyURL = safetyURL
        self.settings = originalSettings
        self.restoredSettings = restoredSettings
    }

    func createArtifact(appVersion: String) async throws -> DatabaseBackupArtifact {
        lock.withLock { artifactCount += 1 }
        return DatabaseBackupArtifact(
            databaseURL: safetyURL,
            settingsData: Data("{}".utf8),
            databaseSchemaVersion: DatabaseSchemaVersion.current,
            appVersion: appVersion,
            databaseByteCount: 100,
            databaseSHA256: "safety-hash"
        )
    }

    func validate(_ backup: DownloadedCloudBackup) async throws -> ValidatedCloudBackup {
        if let error = lock.withLock({ validationError }) { throw error }
        return ValidatedCloudBackup(
            descriptor: backup.descriptor,
            databaseURL: backup.databaseURL,
            settings: restoredSettings
        )
    }

    func restoreDatabase(from url: URL) async throws {
        let result: (Int, Error?) = lock.withLock {
            restoredURLs.append(url)
            return (restoredURLs.count, restoreErrors[restoredURLs.count])
        }
        if let error = result.1 { throw error }
    }

    func migrateRestoredDatabase() async throws {
        lock.withLock { migrationCount += 1 }
    }

    func restoreSettings(_ settings: AppSettings) async {
        lock.withLock { self.settings = settings }
    }

    func currentSettings() async -> AppSettings { lock.withLock { settings } }

    func removeArtifact(at url: URL) {
        lock.withLock { removedURLs.append(url) }
    }

    func setValidationError(_ error: Error?) {
        lock.withLock { validationError = error }
    }

    func setRestoreError(_ error: Error, call: Int) {
        lock.withLock { restoreErrors[call] = error }
    }

    func state() -> State {
        lock.withLock {
            State(
                artifactCount: artifactCount,
                restoredURLs: restoredURLs,
                migrationCount: migrationCount,
                settings: settings,
                removedURLs: removedURLs
            )
        }
    }
}

private actor RestoreSyncSuspender: AppDataSyncSuspending {
    enum Event: Equatable { case suspended, resumed }
    private(set) var events: [Event] = []
    func suspendAndWait() { events.append(.suspended) }
    func resume() { events.append(.resumed) }
}

private actor RestoreCacheInvalidator: BackupCacheInvalidating {
    private(set) var callCount = 0
    func invalidateAfterRestore() async throws { callCount += 1 }
}

private actor RestoreReloadObserver {
    private(set) var callCount = 0
    private var nextError: Error?

    func failNext(with error: Error) { nextError = error }

    func reload() throws {
        callCount += 1
        if let nextError {
            self.nextError = nil
            throw nextError
        }
    }
}
