import Foundation

public struct SettingsBackedTeslamateAPIFactory: Sendable {
    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let clientOverride: (any HTTPClient)?

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        clientOverride: (any HTTPClient)? = nil
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.clientOverride = clientOverride
    }

    public func makeAPI() async -> APIResult<TeslamateAPI> {
        let settings = await settingsStore.load()
        return await makeAPI(settings: settings)
    }

    public func request<Value: Sendable>(
        _ operation: @Sendable (TeslamateAPI) async -> APIResult<Value>
    ) async -> APIResult<Value> {
        let settings = await settingsStore.load()
        let endpoints = await apiConfigurations(settings: settings)
        var lastFailure: APIError?

        for configuration in endpoints {
            switch configuration {
            case let .success(api):
                let result = await operation(api)
                switch result {
                case .success:
                    return result
                case let .failure(error):
                    lastFailure = error
                    guard Self.shouldRetryWithSecondary(after: error) else {
                        return result
                    }
                }
            case let .failure(error):
                lastFailure = error
                guard Self.shouldRetryWithSecondary(after: error) else {
                    return .failure(error)
                }
            }
        }

        return .failure(lastFailure ?? .serverNotConfigured)
    }

    public func makeAPI(settings: AppSettings) async -> APIResult<TeslamateAPI> {
        await makeAPI(settings: settings, serverURL: settings.serverURL)
    }

    private func apiConfigurations(settings: AppSettings) async -> [APIResult<TeslamateAPI>] {
        let urls = [settings.serverURL, settings.secondaryServerURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if urls.isEmpty {
            return [.failure(.serverNotConfigured)]
        }

        var seen: Set<String> = []
        var configurations: [APIResult<TeslamateAPI>] = []
        for candidate in urls {
            guard seen.insert(candidate).inserted else {
                continue
            }
            configurations.append(await makeAPI(settings: settings, serverURL: candidate))
        }
        return configurations
    }

    private func makeAPI(settings: AppSettings, serverURL: String) async -> APIResult<TeslamateAPI> {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return .failure(.serverNotConfigured)
        }
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            return .failure(.invalidURL(trimmedURL))
        }

        let token = Self.nonEmpty(try? await secretStore.get("apiToken"))
        let username = Self.nonEmpty(try? await secretStore.get("httpBasicAuthUsername"))
        let password = Self.nonEmpty(try? await secretStore.get("httpBasicAuthPassword"))
        let basicAuth: BasicAuth?
        if let username, let password {
            basicAuth = BasicAuth(username: username, password: password)
        } else {
            basicAuth = nil
        }

        let cloudflareClientID = Self.nonEmpty(try? await secretStore.get("cloudflareAccessClientID"))
        let cloudflareClientSecret = Self.nonEmpty(try? await secretStore.get("cloudflareAccessClientSecret"))
        let cloudflareAccess = cloudflareClientID.flatMap { clientID in
            cloudflareClientSecret.map { CloudflareAccessAuth(clientID: clientID, clientSecret: $0) }
        }
        let accessKey = Self.nonEmpty(try? await secretStore.get("apiAccessKey"))
        let secretKey = Self.nonEmpty(try? await secretStore.get("apiSecretKey"))
        let aksk = accessKey.flatMap { accessKey in
            secretKey.map { AKSKCredentials(accessKey: accessKey, secretKey: $0) }
        }

        let client = clientOverride ?? URLSessionHTTPClient(acceptsInvalidCertificates: settings.acceptInvalidCerts)
        return .success(TeslamateAPI(
            baseURL: url,
            bearerToken: token,
            basicAuth: basicAuth,
            cloudflareAccess: cloudflareAccess,
            aksk: aksk,
            client: client
        ))
    }

    private static func shouldRetryWithSecondary(after error: APIError) -> Bool {
        switch error {
        case .serverNotConfigured, .invalidURL, .sslCertificate, .network, .invalidResponse, .emptyBody:
            return true
        case let .httpStatus(status):
            return status >= 500 || status == 408 || status == 429
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
