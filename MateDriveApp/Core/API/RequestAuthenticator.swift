import CryptoKit
import Foundation

public struct AKSKCredentials: Equatable, Sendable {
    public let accessKey: String
    public let secretKey: String

    public init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

public enum AKSKRequestSigner {
    public static let algorithm = "TESLAMATEAPI-HMAC-SHA256"

    public static func authenticated(
        _ request: URLRequest,
        credentials: AKSKCredentials,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970),
        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    ) throws -> URLRequest {
        guard let url = request.url else { throw APIError.invalidURL("") }
        var request = request
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data()).hexString
        let canonical = canonicalRequest(
            method: request.httpMethod ?? "GET",
            url: url,
            timestamp: timestamp,
            nonce: nonce,
            bodyHash: bodyHash
        )
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: Data(credentials.secretKey.utf8))
        ).hexString

        request.setValue(credentials.accessKey, forHTTPHeaderField: "X-API-Access-Key")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-API-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-API-Nonce")
        request.setValue(bodyHash, forHTTPHeaderField: "X-API-Content-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-API-Signature")
        return request
    }

    public static func canonicalRequest(
        method: String,
        url: URL,
        timestamp: Int64,
        nonce: String,
        bodyHash: String
    ) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components.flatMap { components in
            components.percentEncodedPath.isEmpty ? nil : components.percentEncodedPath
        } ?? "/"
        return [
            algorithm,
            String(timestamp),
            nonce,
            method.uppercased(),
            path,
            canonicalQuery(components?.queryItems ?? []),
            bodyHash.lowercased()
        ].joined(separator: "\n")
    }

    public static func canonicalQuery(_ queryItems: [URLQueryItem]) -> String {
        queryItems.enumerated()
            .sorted { lhs, rhs in
                lhs.element.name == rhs.element.name ? lhs.offset < rhs.offset : lhs.element.name < rhs.element.name
            }
            .map { "\(percentEncode($0.element.name))=\(percentEncode($0.element.value ?? ""))" }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 65...90, 97...122, 48...57, 45, 46, 95, 126:
                return String(UnicodeScalar(byte))
            default:
                return String(format: "%%%02X", byte)
            }
        }.joined()
    }
}

private extension Sequence where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

public struct CloudflareAccessAuth: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public struct RequestAuthenticator: Equatable, Sendable {
    public static let supportsAKSK = true

    public let bearerToken: String?
    public let basicAuth: BasicAuth?
    public let cloudflareAccess: CloudflareAccessAuth?
    public let aksk: AKSKCredentials?

    public init(
        bearerToken: String? = nil,
        basicAuth: BasicAuth? = nil,
        cloudflareAccess: CloudflareAccessAuth? = nil,
        aksk: AKSKCredentials? = nil
    ) {
        self.bearerToken = Self.nonEmpty(bearerToken)
        self.basicAuth = basicAuth
        self.cloudflareAccess = cloudflareAccess.flatMap { credentials in
            guard let clientID = Self.nonEmpty(credentials.clientID),
                  let clientSecret = Self.nonEmpty(credentials.clientSecret)
            else {
                return nil
            }
            return CloudflareAccessAuth(clientID: clientID, clientSecret: clientSecret)
        }
        self.aksk = aksk.flatMap { credentials in
            guard let accessKey = Self.nonEmpty(credentials.accessKey),
                  let secretKey = Self.nonEmpty(credentials.secretKey)
            else { return nil }
            return AKSKCredentials(accessKey: accessKey, secretKey: secretKey)
        }
    }

    public func authenticated(_ request: URLRequest) throws -> URLRequest {
        var request = request
        if let basicAuth {
            let raw = "\(basicAuth.username):\(basicAuth.password)"
            let basicHeader = "Basic \(Data(raw.utf8).base64EncodedString())"
            if let bearerToken {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                request.setValue(basicHeader, forHTTPHeaderField: "X-MateDrive-Basic-Authorization")
            } else {
                request.setValue(basicHeader, forHTTPHeaderField: "Authorization")
            }
        } else if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let cloudflareAccess {
            request.setValue(cloudflareAccess.clientID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(cloudflareAccess.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        if let aksk {
            request = try AKSKRequestSigner.authenticated(request, credentials: aksk)
        }
        return request
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
