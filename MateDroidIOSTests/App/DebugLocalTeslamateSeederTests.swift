import XCTest
@testable import MateDroidIOS

final class DebugLocalTeslamateSeederTests: XCTestCase {
    func testIntegrationConfigPrefersMateDriveEnvironmentVariables() {
        let config = DebugLocalTeslamateSeeder.integrationConfig(from: [
            "MATEDROID_INTEGRATION_BASE_URL": "http://old.example",
            "MATEDROID_INTEGRATION_API_TOKEN": "old-token",
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

    func testSeedKeepsLegacyMateDroidEnvironmentFallback() async {
        let settingsStore = InMemorySeederSettingsStore()
        let secretStore = InMemorySeederSecretStore()

        await DebugLocalTeslamateSeeder.seedIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: [
                "MATEDROID_INTEGRATION_BASE_URL": "http://127.0.0.1:3030",
                "MATEDROID_INTEGRATION_API_TOKEN": "legacy-token"
            ]
        )

        let settings = await settingsStore.load()
        let token = try? await secretStore.get("apiToken")
        XCTAssertEqual(settings.serverURL, "http://127.0.0.1:3030")
        XCTAssertEqual(token, "legacy-token")
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
