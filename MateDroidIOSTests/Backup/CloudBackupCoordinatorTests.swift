import XCTest
@testable import MateDroidIOS

final class CloudBackupCoordinatorTests: XCTestCase {
    func testManualBackupRequiresDisclosureAndThenUploads() async throws {
        let fixture = makeFixture()

        do {
            _ = try await fixture.coordinator.createManualBackup()
            XCTFail("Expected disclosure requirement")
        } catch let error as CloudBackupError {
            XCTAssertEqual(error, .disclosureRequired)
        }

        await fixture.coordinator.acceptDisclosure()
        let saved = try await fixture.coordinator.createManualBackup()
        let counts = await fixture.service.counts()
        let removedCount = await fixture.database.removedArtifactCount()

        XCTAssertEqual(saved.kind, .manual)
        XCTAssertEqual(counts.uploads, 1)
        XCTAssertEqual(removedCount, 1)
    }

    func testAutomaticBackupNeedsSuccessfulSyncAndRunsAtMostOncePerDay() async throws {
        let clock = BackupTestClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let fixture = makeFixture(clock: clock)
        await fixture.coordinator.acceptDisclosure()
        try await fixture.coordinator.setAutomaticBackupEnabled(true)

        let failed = BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [], failedCarIDs: [1]),
            vehicleStatusRefreshed: false
        )
        let failedResult = await fixture.coordinator.createAutomaticBackup(after: failed)
        XCTAssertNil(failedResult)

        let success = BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: []),
            vehicleStatusRefreshed: true
        )
        let firstResult = await fixture.coordinator.createAutomaticBackup(after: success)
        let duplicateResult = await fixture.coordinator.createAutomaticBackup(after: success)
        XCTAssertNotNil(firstResult)
        XCTAssertNil(duplicateResult)

        clock.advance(by: 24 * 60 * 60)
        let nextDayResult = await fixture.coordinator.createAutomaticBackup(after: success)
        let counts = await fixture.service.counts()
        XCTAssertNotNil(nextDayResult)
        XCTAssertEqual(counts.uploads, 2)
    }

    func testSuccessfulUploadRetainsNewestThreeBackups() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = (1...3).map { index in
            CloudBackupDescriptor(
                id: "old-\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index * 60)),
                kind: .manual,
                formatVersion: 1,
                databaseSchemaVersion: 19,
                appVersion: "1.0",
                databaseByteCount: 10,
                databaseSHA256: "hash"
            )
        }
        let fixture = makeFixture(
            clock: BackupTestClock(now: now),
            existing: existing
        )
        await fixture.coordinator.acceptDisclosure()

        _ = try await fixture.coordinator.createManualBackup()

        let counts = await fixture.service.counts()
        let cached = try await fixture.coordinator.listBackups(forceRefresh: false)
        XCTAssertEqual(counts.deletions, ["old-3"])
        XCTAssertEqual(cached.count, 3)
    }

    func testRetentionFailureDoesNotInvalidateNewBackup() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = (1...3).map { index in
            CloudBackupDescriptor(
                id: "old-\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                kind: .manual,
                formatVersion: 1,
                databaseSchemaVersion: 19,
                appVersion: "1.0",
                databaseByteCount: 10,
                databaseSHA256: "hash"
            )
        }
        let fixture = makeFixture(clock: BackupTestClock(now: now), existing: existing)
        await fixture.service.setDeleteError(CloudBackupError.iCloudUnavailable)
        await fixture.coordinator.acceptDisclosure()

        let saved = try await fixture.coordinator.createManualBackup()
        let warning = await fixture.coordinator.cleanupWarning()

        XCTAssertEqual(saved.id, "uploaded-1")
        XCTAssertNotNil(warning)
    }

    private func makeFixture(
        clock: BackupTestClock = BackupTestClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
        existing: [CloudBackupDescriptor] = []
    ) -> (
        coordinator: CloudBackupCoordinator,
        service: InMemoryCloudBackupService,
        database: CoordinatorDatabaseBackupProvider
    ) {
        let service = InMemoryCloudBackupService(descriptors: existing, now: { clock.value() })
        let database = CoordinatorDatabaseBackupProvider()
        let preferences = CoordinatorPreferencesStore()
        let coordinator = CloudBackupCoordinator(
            service: service,
            databaseProvider: database,
            preferencesStore: preferences,
            appVersion: { "1.0" },
            now: { clock.value() }
        )
        return (coordinator, service, database)
    }
}

private final class BackupTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date

    init(now: Date) { self.now = now }
    func value() -> Date { lock.withLock { now } }
    func advance(by interval: TimeInterval) { lock.withLock { now = now.addingTimeInterval(interval) } }
}

private actor CoordinatorPreferencesStore: CloudBackupPreferencesStoring {
    private var preferences = CloudBackupPreferences()
    func load() -> CloudBackupPreferences { preferences }
    func save(_ preferences: CloudBackupPreferences) { self.preferences = preferences }
}

private final class CoordinatorDatabaseBackupProvider: DatabaseBackupProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var removedCount = 0
    private var settings = AppSettings()

    func createArtifact(appVersion: String) async throws -> DatabaseBackupArtifact {
        DatabaseBackupArtifact(
            databaseURL: URL(fileURLWithPath: "/tmp/fake-backup.sqlite"),
            settingsData: Data("{}".utf8),
            databaseSchemaVersion: DatabaseSchemaVersion.current,
            appVersion: appVersion,
            databaseByteCount: 100,
            databaseSHA256: "hash"
        )
    }

    func validate(_ backup: DownloadedCloudBackup) async throws -> ValidatedCloudBackup {
        ValidatedCloudBackup(descriptor: backup.descriptor, databaseURL: backup.databaseURL, settings: settings)
    }

    func restoreDatabase(from url: URL) async throws {}
    func restoreSettings(_ settings: AppSettings) async { lock.withLock { self.settings = settings } }
    func currentSettings() async -> AppSettings { lock.withLock { settings } }
    func removeArtifact(at url: URL) { lock.withLock { removedCount += 1 } }
    func removedArtifactCount() async -> Int { lock.withLock { removedCount } }
}

private extension InMemoryCloudBackupService {
    func setDeleteError(_ error: Error?) {
        deleteError = error
    }
}
