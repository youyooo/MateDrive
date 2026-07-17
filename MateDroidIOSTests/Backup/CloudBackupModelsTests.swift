import XCTest
@testable import MateDroidIOS

@MainActor
final class CloudBackupModelsTests: XCTestCase {
    func testCloudBackupPreferencesDefaultToPrivateOptInDisabled() {
        let preferences = CloudBackupPreferences()

        XCTAssertFalse(preferences.hasAcceptedDisclosure)
        XCTAssertFalse(preferences.isAutomaticBackupEnabled)
        XCTAssertNil(preferences.lastAutomaticBackupAt)
        XCTAssertTrue(preferences.cachedBackups.isEmpty)
    }

    func testPreferencesStoreRoundTripsConsentAndCachedMetadata() async throws {
        let suiteName = "CloudBackupModelsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsCloudBackupPreferencesStore(defaults: defaults)
        let descriptor = CloudBackupDescriptor(
            id: "backup-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .manual,
            formatVersion: 1,
            databaseSchemaVersion: 19,
            appVersion: "1.0",
            databaseByteCount: 1024,
            databaseSHA256: "abc"
        )
        let expected = CloudBackupPreferences(
            hasAcceptedDisclosure: true,
            isAutomaticBackupEnabled: true,
            lastAutomaticBackupAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastSuccessfulBackupAt: descriptor.createdAt,
            cachedBackups: [descriptor]
        )

        await store.save(expected)

        let restored = await store.load()
        XCTAssertEqual(restored, expected)
    }
}
