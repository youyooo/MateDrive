import Foundation
import Security

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public let acceptsInvalidCertificates: Bool
    private let session: URLSession

    public init(session: URLSession, acceptsInvalidCertificates: Bool = false) {
        self.session = session
        self.acceptsInvalidCertificates = acceptsInvalidCertificates
    }

    public init(acceptsInvalidCertificates: Bool = false) {
        self.acceptsInvalidCertificates = acceptsInvalidCertificates
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(
            configuration: configuration,
            delegate: RestrictedURLSessionDelegate(
                acceptsInvalidCertificates: acceptsInvalidCertificates
            ),
            delegateQueue: nil
        )
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse("Response was not HTTPURLResponse")
        }
        return (data, http)
    }
}

public enum HTTPRedirectPolicy {
    public static func allowsRedirect(from source: URL?, to destination: URL?) -> Bool {
        guard let source,
              let destination,
              let sourceScheme = source.scheme?.lowercased(),
              let destinationScheme = destination.scheme?.lowercased(),
              let sourceHost = source.host?.lowercased(),
              let destinationHost = destination.host?.lowercased(),
              sourceHost == destinationHost
        else {
            return false
        }
        guard sourceScheme == destinationScheme
                || (sourceScheme == "http" && destinationScheme == "https")
        else {
            return false
        }

        let sourcePort = effectivePort(for: source)
        let destinationPort = effectivePort(for: destination)
        if sourceScheme == "http",
           destinationScheme == "https",
           sourcePort == 80,
           destinationPort == 443
        {
            return true
        }
        return sourcePort == destinationPort
    }

    private static func effectivePort(for url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}

private final class RestrictedURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let acceptsInvalidCertificates: Bool

    init(acceptsInvalidCertificates: Bool) {
        self.acceptsInvalidCertificates = acceptsInvalidCertificates
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard acceptsInvalidCertificates,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        HTTPRedirectPolicy.allowsRedirect(from: response.url, to: request.url)
            ? request
            : nil
    }
}
