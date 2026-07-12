import Foundation
import Security

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public let acceptsInvalidCertificates: Bool
    private let session: URLSession

    public init(session: URLSession = .shared, acceptsInvalidCertificates: Bool = false) {
        self.session = session
        self.acceptsInvalidCertificates = acceptsInvalidCertificates
    }

    public init(acceptsInvalidCertificates: Bool) {
        self.acceptsInvalidCertificates = acceptsInvalidCertificates
        if acceptsInvalidCertificates {
            let configuration = URLSessionConfiguration.ephemeral
            self.session = URLSession(
                configuration: configuration,
                delegate: InvalidCertificateURLSessionDelegate(),
                delegateQueue: nil
            )
        } else {
            self.session = .shared
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse("Response was not HTTPURLResponse")
        }
        return (data, http)
    }
}

private final class InvalidCertificateURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: serverTrust))
    }
}
