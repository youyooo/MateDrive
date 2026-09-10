import XCTest
@testable import MateDriveApp

final class DebugLocalTeslamateSeederTests: XCTestCase {
    func testIntegrationConfigPrefersMateDriveEnvironmentVariables() {
        let config = DebugLocalTeslamateSeeder.integrationConfig(from: [
            "MATEDRIVE_INTEGRATION_BASE_URL": " http://new.example ",
            "MATEDRIVE_INTEGRATION_API_TOKEN": " new-token ",
            "MATEDRIVE_INTEGRATION_BASIC_USERNAME": " alice ",
            "MATEDRIVE_INTEGRATION_BASIC_PASSWORD": " secret "
        ])

        XCTAssertEqual(config?.baseURL, "http://new.example")
        XCTAssertEqual(config?.token, "new-token")
        XCTAssertEqual(config?.basicUsername, "alice")
        XCTAssertEqual(config?.basicPassword, "secret")
    }

    func testSeedStoresBasicAuthWhenProvided() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()

        await DebugLocalTeslamateSeeder.seedIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: [
                "MATEDRIVE_INTEGRATION_BASE_URL": "http://127.0.0.1:3030",
                "MATEDRIVE_INTEGRATION_BASIC_USERNAME": "local-user",
                "MATEDRIVE_INTEGRATION_BASIC_PASSWORD": "local-pass"
            ]
        )

        let settings = await settingsStore.load()
        let username = try? await secretStore.get("httpBasicAuthUsername")
        let password = try? await secretStore.get("httpBasicAuthPassword")
        XCTAssertEqual(settings.serverURL, "http://127.0.0.1:3030")
        XCTAssertEqual(settings.authenticationMode, .basic)
        XCTAssertEqual(username, "local-user")
        XCTAssertEqual(password, "local-pass")
    }

    func testIntegrationConfigAllowsLocalBaseURLWithoutAuth() {
        let config = DebugLocalTeslamateSeeder.integrationConfig(from: [
            "MATEDRIVE_INTEGRATION_BASE_URL": " http://127.0.0.1:3030 "
        ])

        XCTAssertEqual(config?.baseURL, "http://127.0.0.1:3030")
        XCTAssertNil(config?.token)
        XCTAssertNil(config?.basicUsername)
        XCTAssertNil(config?.basicPassword)
    }

    func testUITestModeSeedsConfiguredVehicleWithoutCredentials() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()
        await DashboardSnapshotStore.shared.clearAll()

        await DebugLocalTeslamateSeeder.seedIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: ["MATEDRIVE_UI_TEST_MODE": "1"]
        )

        let settings = await settingsStore.load()
        XCTAssertEqual(settings.serverURL, "https://ui-test.invalid")
        XCTAssertEqual(settings.authenticationMode, .none)
        XCTAssertEqual(settings.lastSelectedCarId, 1)
        XCTAssertEqual(settings.appLanguage, .chinese)
        let apiToken = try? await secretStore.get("apiToken")
        XCTAssertNil(apiToken)
        await DashboardSnapshotStore.shared.clearAll()
    }

    func testFreshSetupUITestModeResetsPreviouslyConfiguredServer() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()
        await settingsStore.save(AppSettings(serverURL: "https://previous.example"))
        try? await secretStore.set("previous-token", for: "apiToken")
        try? await secretStore.set("previous-client", for: "cloudflareAccessClientID")

        await DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: [
                "MATEDRIVE_UI_TEST_MODE": "1",
                "MATEDRIVE_UI_TEST_FRESH_SETUP": "1",
                "MATEDRIVE_UI_TEST_LANGUAGE": "en"
            ]
        )

        let settings = await settingsStore.load()
        let storedToken = try? await secretStore.get("apiToken")
        let storedCloudflareClientID = try? await secretStore.get("cloudflareAccessClientID")
        XCTAssertFalse(settings.isConfigured)
        XCTAssertEqual(settings.appLanguage, .english)
        XCTAssertNil(storedToken)
        XCTAssertNil(storedCloudflareClientID)
    }

    func testUITestModeCanPreserveSavedSettingsAcrossRelaunch() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()
        let savedSettings = AppSettings(
            serverURL: "http://127.0.0.1:3030",
            authenticationMode: .none
        )
        await settingsStore.save(savedSettings)

        await DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: [
                "MATEDRIVE_UI_TEST_MODE": "1",
                "MATEDRIVE_UI_TEST_PRESERVE_SETTINGS": "1"
            ]
        )

        let reloaded = await settingsStore.load()
        XCTAssertEqual(reloaded.serverURL, savedSettings.serverURL)
        XCTAssertEqual(reloaded.authenticationMode, savedSettings.authenticationMode)
    }

    func testUITestModeCanSeedEveryExplicitReleaseLanguage() async {
        let cases: [(environmentValue: String, expected: AppLanguage)] = [
            ("en", .english),
            ("zh-Hans", .chinese),
            ("zh-Hant", .traditionalChinese)
        ]

        for testCase in cases {
            let settingsStore = InMemorySeederSettingsStore()
            let secretStore = InMemorySeederSecretStore()
            await DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded(
                settingsStore: settingsStore,
                secretStore: secretStore,
                environment: [
                    "MATEDRIVE_UI_TEST_MODE": "1",
                    "MATEDRIVE_UI_TEST_LANGUAGE": testCase.environmentValue
                ]
            )

            let settings = await settingsStore.load()
            XCTAssertEqual(settings.appLanguage, testCase.expected)
        }
        await DashboardSnapshotStore.shared.clearAll()
    }

    func testUITestLaunchConfigurationCanSeedWithoutOpeningDatabase() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()
        await DashboardSnapshotStore.shared.clearAll()

        await DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: ["MATEDRIVE_UI_TEST_MODE": "1"]
        )

        let settings = await settingsStore.load()
        let snapshot = await DashboardSnapshotStore.shared.load(
            serverURL: "https://ui-test.invalid",
            carId: 1
        )
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(snapshot?.state(errorMessage: "").selectedCarId, 1)
        await DashboardSnapshotStore.shared.clearAll()
    }

    func testUITestDatabaseSeedRemovesScreenshotOnlySessionsBeforeNavigation() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let provider = SeederDatabaseProvider(database: database)

        await DebugLocalTeslamateSeeder.seedDatabaseFixtureIfNeeded(
            databaseProvider: provider,
            environment: [
                "MATEDRIVE_UI_TEST_MODE": "1",
                "MATEDRIVE_STORE_SCREENSHOT_MODE": "1"
            ]
        )
        let driveRecords = try await DriveSummaryStore(database: database).records(carId: 1)
        let seededDriveStart = try XCTUnwrap(
            DomainDateParser.date(from: try XCTUnwrap(driveRecords.first?.startDate))
        )
        XCTAssertLessThan(Date().timeIntervalSince(seededDriveStart), 7 * 24 * 60 * 60)
        let store = SmartActivityStore(database: database)
        let screenshotSessions = try await store.sessions(carId: 1)
        XCTAssertTrue(screenshotSessions.contains { session in
            session.eventReferences.contains { $0.kind == .charge }
        })

        await DebugLocalTeslamateSeeder.seedDatabaseFixtureIfNeeded(
            databaseProvider: provider,
            environment: ["MATEDRIVE_UI_TEST_MODE": "1"]
        )
        let navigationSessions = try await store.sessions(carId: 1)

        XCTAssertEqual(navigationSessions.map(\.id), ["ui-session-1"])
        XCTAssertFalse(navigationSessions.contains { session in
            session.eventReferences.contains { $0.kind == .charge }
        })
    }
}

private final class InMemorySeederSettingsStore: SettingsStoring, @unchecked Sendable {
    private var settings = AppSettings()

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        self.settings = settings
    }
}

private final class InMemorySeederSecretStore: SecretStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    func get(_ key: String) async throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: String) async throws {
        values[key] = value
    }

    func remove(_ key: String) async throws {
        values.removeValue(forKey: key)
    }
}

private struct SeederDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase {
        database
    }
}
