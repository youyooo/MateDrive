import Foundation

public enum TeslaMateServerURLPolicy: Equatable, Sendable {
    case secureRemote
    case localHTTP
    case insecureRemoteHTTP
    case invalid

    public static func evaluate(_ value: String) -> TeslaMateServerURLPolicy {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              !containsSensitiveComponents(components),
              let url = components.url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isReservedInvalidHost(host) else {
            return .invalid
        }
        if scheme == "https" {
            return .secureRemote
        }
        guard scheme == "http" else {
            return .invalid
        }
        return isLocalHost(host) ? .localHTTP : .insecureRemoteHTTP
    }

    public var isUsable: Bool {
        self == .secureRemote || self == .localHTTP
    }

    public static func permitsInvalidCertificateBypass(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              !containsSensitiveComponents(components),
              let url = components.url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isReservedInvalidHost(host) else {
            return false
        }
        return isLocalHost(host)
    }

    public static func containsEmbeddedSecrets(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return containsSensitiveComponents(components)
    }

    public static func isLocalNetworkHost(_ value: String) -> Bool {
        guard let host = parsedHost(from: value) else {
            return false
        }
        return isLocalHost(host)
    }

    public static func isTailscaleHost(_ value: String) -> Bool {
        guard let host = parsedHost(from: value) else {
            return false
        }
        return host.hasSuffix(".ts.net")
    }

    private static func containsSensitiveComponents(_ components: URLComponents) -> Bool {
        components.user != nil
            || components.password != nil
            || components.percentEncodedQuery != nil
            || components.fragment != nil
    }

    private static func parsedHost(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              !containsSensitiveComponents(components),
              let url = components.url,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isReservedInvalidHost(host) else {
            return nil
        }
        return host
    }

    private static func isReservedInvalidHost(_ host: String) -> Bool {
        host == "invalid" || host.hasSuffix(".invalid")
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".ts.net") || !host.contains(".") {
            return true
        }
        if host.contains(":"),
           host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0 ... 255).contains($0) }) else {
            return false
        }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, 16 ... 31), (100, 64 ... 127):
            return true
        default:
            return false
        }
    }
}

struct ServerAuthenticationDraft: Sendable {
    var apiToken: String?
    var basicUsername: String?
    var basicPassword: String?
    var cloudflareClientID: String?
    var cloudflareClientSecret: String?
    var apiAccessKey: String?
    var apiSecretKey: String?
}

enum ServerAuthenticationResolver {
    static func resolve(
        settings: AppSettings,
        secretStore: any SecretStoring,
        draft: ServerAuthenticationDraft = ServerAuthenticationDraft()
    ) async -> RequestAuthenticator {
        let coreAuthentication: (String?, BasicAuth?, AKSKCredentials?)
        switch settings.authenticationMode {
        case .automatic:
            async let token = value(draft.apiToken, storedAs: "apiToken", in: secretStore)
            async let username = value(draft.basicUsername, storedAs: "httpBasicAuthUsername", in: secretStore)
            async let password = value(draft.basicPassword, storedAs: "httpBasicAuthPassword", in: secretStore)
            async let accessKey = value(draft.apiAccessKey, storedAs: "apiAccessKey", in: secretStore)
            async let secretKey = value(draft.apiSecretKey, storedAs: "apiSecretKey", in: secretStore)
            let values = await (token, username, password, accessKey, secretKey)
            coreAuthentication = (
                values.0,
                basicAuth(username: values.1, password: values.2),
                aksk(accessKey: values.3, secretKey: values.4)
            )
        case .none:
            coreAuthentication = (nil, nil, nil)
        case .bearerToken:
            let token = await value(draft.apiToken, storedAs: "apiToken", in: secretStore)
            coreAuthentication = (token, nil, nil)
        case .basic:
            async let username = value(draft.basicUsername, storedAs: "httpBasicAuthUsername", in: secretStore)
            async let password = value(draft.basicPassword, storedAs: "httpBasicAuthPassword", in: secretStore)
            let credentials = await (username, password)
            coreAuthentication = (nil, basicAuth(username: credentials.0, password: credentials.1), nil)
        case .apiKeys:
            async let accessKey = value(draft.apiAccessKey, storedAs: "apiAccessKey", in: secretStore)
            async let secretKey = value(draft.apiSecretKey, storedAs: "apiSecretKey", in: secretStore)
            let credentials = await (accessKey, secretKey)
            coreAuthentication = (nil, nil, aksk(accessKey: credentials.0, secretKey: credentials.1))
        }

        let shouldUseCloudflare = settings.authenticationMode == .automatic || settings.usesCloudflareAccess
        let cloudflareAccess: CloudflareAccessAuth?
        if shouldUseCloudflare {
            let clientID = await value(draft.cloudflareClientID, storedAs: "cloudflareAccessClientID", in: secretStore)
            let clientSecret = await value(draft.cloudflareClientSecret, storedAs: "cloudflareAccessClientSecret", in: secretStore)
            cloudflareAccess = clientID.flatMap { clientID in
                clientSecret.map { CloudflareAccessAuth(clientID: clientID, clientSecret: $0) }
            }
        } else {
            cloudflareAccess = nil
        }

        return RequestAuthenticator(
            bearerToken: coreAuthentication.0,
            basicAuth: coreAuthentication.1,
            cloudflareAccess: cloudflareAccess,
            aksk: coreAuthentication.2
        )
    }

    private static func basicAuth(username: String?, password: String?) -> BasicAuth? {
        username.flatMap { username in
            password.map { BasicAuth(username: username, password: $0) }
        }
    }

    private static func aksk(accessKey: String?, secretKey: String?) -> AKSKCredentials? {
        accessKey.flatMap { accessKey in
            secretKey.map { AKSKCredentials(accessKey: accessKey, secretKey: $0) }
        }
    }

    private static func value(
        _ formValue: String?,
        storedAs key: String,
        in secretStore: any SecretStoring
    ) async -> String? {
        if let formValue = nonEmpty(formValue) {
            return formValue
        }
        return nonEmpty(try? await secretStore.get(key))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct SettingsBackedTeslamateAPIFactory: Sendable {
    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let clientOverride: (any HTTPClient)?
    private let networkPolicy: APIRequestNetworkPolicy

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        clientOverride: (any HTTPClient)? = nil,
        networkPolicy: APIRequestNetworkPolicy = .online
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.clientOverride = clientOverride
        self.networkPolicy = networkPolicy
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
            return .failure(.invalidURL(Self.safeInvalidURLDescription(trimmedURL)))
        }
        guard TeslaMateServerURLPolicy.evaluate(trimmedURL).isUsable else {
            return .failure(.invalidURL(Self.safeInvalidURLDescription(trimmedURL)))
        }

        let authenticator = await ServerAuthenticationResolver.resolve(settings: settings, secretStore: secretStore)

        let baseClient: any HTTPClient
        if let clientOverride {
            baseClient = clientOverride
        } else {
            let acceptsInvalidCertificates = settings.acceptInvalidCerts
                && TeslaMateServerURLPolicy.permitsInvalidCertificateBypass(trimmedURL)
            let upstream = URLSessionHTTPClient(acceptsInvalidCertificates: acceptsInvalidCertificates)
            baseClient = CachedHTTPClient(
                upstream: upstream,
                namespace: acceptsInvalidCertificates ? "teslamate-insecure" : "teslamate-secure"
            )
        }
        let client: any HTTPClient
        switch networkPolicy {
        case .online:
            client = baseClient
        case .cacheOnly:
            client = NetworkPolicyHTTPClient(upstream: baseClient, policy: .cacheOnly)
        }
        return .success(TeslamateAPI(
            baseURL: url,
            bearerToken: authenticator.bearerToken,
            basicAuth: authenticator.basicAuth,
            cloudflareAccess: authenticator.cloudflareAccess,
            aksk: authenticator.aksk,
            client: client
        ))
    }

    private static func shouldRetryWithSecondary(after error: APIError) -> Bool {
        switch error {
        case .serverNotConfigured, .invalidURL, .sslCertificate, .network, .invalidResponse, .emptyBody:
            return true
        case .cancelled:
            return false
        case let .httpStatus(status):
            return status >= 500 || status == 408 || status == 429
        }
    }

    private static func safeInvalidURLDescription(_ value: String) -> String {
        TeslaMateServerURLPolicy.containsEmbeddedSecrets(value) ? "[redacted]" : value
    }
}
