import Foundation

#if DEBUG
enum DebugLocalTeslamateSeeder {
    struct IntegrationConfig: Equatable {
        let baseURL: String
        let token: String?
        let basicUsername: String?
        let basicPassword: String?
    }

    static func seedIfNeeded(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        guard let config = integrationConfig(from: environment) else {
            return
        }

        var settings = await settingsStore.load()
        settings.serverURL = config.baseURL
        await settingsStore.save(settings)
        if let token = config.token {
            try? await secretStore.set(token, for: "apiToken")
        }
        if let username = config.basicUsername {
            try? await secretStore.set(username, for: "httpBasicAuthUsername")
        }
        if let password = config.basicPassword {
            try? await secretStore.set(password, for: "httpBasicAuthPassword")
        }
    }

    static func integrationConfig(from environment: [String: String]) -> IntegrationConfig? {
        let baseURL = firstNonEmpty(
            environment["MATEDRIVE_INTEGRATION_BASE_URL"],
            environment["MATEDROID_INTEGRATION_BASE_URL"]
        )
        let token = firstNonEmpty(
            environment["MATEDRIVE_INTEGRATION_API_TOKEN"],
            environment["MATEDROID_INTEGRATION_API_TOKEN"]
        )
        let basicUsername = firstNonEmpty(
            environment["MATEDRIVE_INTEGRATION_BASIC_USERNAME"],
            environment["MATEDROID_INTEGRATION_BASIC_USERNAME"]
        )
        let basicPassword = firstNonEmpty(
            environment["MATEDRIVE_INTEGRATION_BASIC_PASSWORD"],
            environment["MATEDROID_INTEGRATION_BASIC_PASSWORD"]
        )

        guard let baseURL else {
            return nil
        }
        return IntegrationConfig(
            baseURL: baseURL,
            token: token,
            basicUsername: basicUsername,
            basicPassword: basicPassword
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
#endif
