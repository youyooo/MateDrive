import Foundation

public enum APIError: Error, Equatable, Sendable {
    case serverNotConfigured
    case invalidURL(String)
    case httpStatus(Int)
    case sslCertificate(String)
    case invalidResponse(String)
    case network(String)
    case cancelled
    case emptyBody

    static func from(_ error: Error) -> APIError {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        return .network(error.localizedDescription)
    }
}
