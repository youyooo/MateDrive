import XCTest
@testable import MateDriveApp

final class AppDatabaseProviderTests: XCTestCase {
    func testDatabaseProviderCreatesMateDriveDatabaseForNewInstall() async throws {
        let baseDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let provider = LiveAppDatabaseProvider(applicationSupportBaseDirectory: baseDirectory)
        _ = try await provider.database()

        let databaseURL = baseDirectory.appending(path: "MateDrive/matedrive.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        XCTAssertTrue(
            protection == nil || protection == .completeUntilFirstUserAuthentication,
            "The simulator may omit NSFileProtectionKey, but must not report a weaker explicit protection class."
        )
#else
        XCTAssertEqual(
            protection,
            .completeUntilFirstUserAuthentication
        )
#endif
    }

    func testConfiguredServersUseIndependentDatabasesAndRestoreTheirOwnCacheWhenSelectedAgain() async throws {
        let baseDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let settingsStore = MutableDatabaseSettingsStore(
            settings: AppSettings(serverURL: "https://first.example")
        )
        let provider = LiveAppDatabaseProvider(
            applicationSupportBaseDirectory: baseDirectory,
            settingsStore: settingsStore
        )

        let firstDatabase = try await provider.database()
        try await firstDatabase.execute("CREATE TABLE server_marker (value TEXT NOT NULL);")
        try await firstDatabase.run(
            "INSERT INTO server_marker (value) VALUES (?);",
            bindings: [.text("first")]
        )

        await settingsStore.save(AppSettings(serverURL: "https://second.example"))
        let secondDatabase = try await provider.database()
        let secondTablesBeforeInsert = try await secondDatabase.tableNames()
        XCTAssertFalse(secondTablesBeforeInsert.contains("server_marker"))
        try await secondDatabase.execute("CREATE TABLE server_marker (value TEXT NOT NULL);")
        try await secondDatabase.run(
            "INSERT INTO server_marker (value) VALUES (?);",
            bindings: [.text("second")]
        )

        await settingsStore.save(AppSettings(serverURL: "https://first.example"))
        let restoredFirstDatabase = try await provider.database()
        let firstValues = try await restoredFirstDatabase.textValues("SELECT value FROM server_marker;")
        let secondValues = try await secondDatabase.textValues("SELECT value FROM server_marker;")
        XCTAssertEqual(firstValues, ["first"])
        XCTAssertEqual(secondValues, ["second"])
    }

    func testLegacyDatabaseIsAdoptedOnlyByFirstConfiguredServer() async throws {
        let baseDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let legacyProvider = LiveAppDatabaseProvider(
            applicationSupportBaseDirectory: baseDirectory
        )
        let legacyDatabase = try await legacyProvider.database()
        try await legacyDatabase.execute("CREATE TABLE legacy_marker (value TEXT NOT NULL);")
        try await legacyDatabase.run(
            "INSERT INTO legacy_marker (value) VALUES (?);",
            bindings: [.text("legacy")]
        )

        let settingsStore = MutableDatabaseSettingsStore(
            settings: AppSettings(serverURL: "https://first.example")
        )
        let scopedProvider = LiveAppDatabaseProvider(
            applicationSupportBaseDirectory: baseDirectory,
            settingsStore: settingsStore
        )
        let firstDatabase = try await scopedProvider.database()
        let adoptedValues = try await firstDatabase.textValues("SELECT value FROM legacy_marker;")
        XCTAssertEqual(adoptedValues, ["legacy"])

        await settingsStore.save(AppSettings(serverURL: "https://second.example"))
        let secondDatabase = try await scopedProvider.database()
        let secondTables = try await secondDatabase.tableNames()
        XCTAssertFalse(secondTables.contains("legacy_marker"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "MateDriveDatabaseProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private actor MutableDatabaseSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}
