import Foundation

public enum APIError: Error, Equatable, Sendable {
    case serverNotConfigured
    case invalidURL(String)
    case httpStatus(Int)
    case sslCertificate(String)
    case invalidResponse(String)
    case network(String)
    case emptyBody
}
