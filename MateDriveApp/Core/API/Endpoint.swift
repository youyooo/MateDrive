import Foundation

public struct BasicAuth: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct Endpoint: Equatable, Sendable {
    public let baseURL: URL
    public let path: String
    public let queryItems: [URLQueryItem]
    public let authenticator: RequestAuthenticator

    public init(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        bearerToken: String? = nil,
        basicAuth: BasicAuth? = nil,
        authenticator: RequestAuthenticator? = nil
    ) {
        self.baseURL = baseURL
        self.path = path
        self.queryItems = queryItems
        self.authenticator = authenticator ?? RequestAuthenticator(
            bearerToken: bearerToken,
            basicAuth: basicAuth
        )
    }

    public func request() throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw APIError.invalidURL(path)
        }

        return try authenticator.authenticated(URLRequest(url: url))
    }
}
