import Foundation
import XCTest
@testable import MateDroidIOS

final class RequestAuthenticatorTests: XCTestCase {
    func testAuthenticatorPreservesBearerAndProxyBasicHeaders() throws {
        let authenticator = RequestAuthenticator(
            bearerToken: " token-123 ",
            basicAuth: BasicAuth(username: "alice", password: "secret")
        )

        let request = try authenticator.authenticated(URLRequest(url: URL(string: "https://example.com/api/v1/cars")!))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MateDrive-Basic-Authorization"), "Basic YWxpY2U6c2VjcmV0")
    }

    func testAuthenticatorAddsCloudflareAccessHeadersWithoutReplacingBearer() throws {
        let authenticator = RequestAuthenticator(
            bearerToken: "token-123",
            cloudflareAccess: CloudflareAccessAuth(clientID: "cf-id", clientSecret: "cf-secret")
        )

        let request = try authenticator.authenticated(URLRequest(url: URL(string: "https://example.com/api/v1/cars")!))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "cf-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "cf-secret")
    }

    func testAKSKCanonicalRequestMatchesTeslaMateAPI251Contract() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/api/v1/version?b=two&a=hello%20world&a=one&empty="))
        let canonical = AKSKRequestSigner.canonicalRequest(
            method: "get",
            url: url,
            timestamp: 1_783_770_000,
            nonce: "0123456789abcdef0123456789abcdef",
            bodyHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )

        XCTAssertTrue(RequestAuthenticator.supportsAKSK)
        XCTAssertEqual(canonical, """
        TESLAMATEAPI-HMAC-SHA256
        1783770000
        0123456789abcdef0123456789abcdef
        GET
        /api/v1/version
        a=hello%20world&a=one&b=two&empty=
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """)
    }

    func testAKSKSignerAddsOfficialHeadersAndKnownSignature() throws {
        let credentials = AKSKCredentials(accessKey: "AKMateDriveProbe251", secretKey: "SKMateDriveProbe251Secret")
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/version?b=two&a=hello%20world&a=one&empty=")!)

        let signed = try AKSKRequestSigner.authenticated(
            request,
            credentials: credentials,
            timestamp: 1_783_770_000,
            nonce: "0123456789abcdef0123456789abcdef"
        )

        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Access-Key"), "AKMateDriveProbe251")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Timestamp"), "1783770000")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Nonce"), "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Content-SHA256"), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Signature"), "1379b1dfe001e59e35156160b2ab529295f6d423f7b926446f2b1cfa10f35380")
    }

    func testAKSKSignerHashesRequestBody() throws {
        var request = URLRequest(url: URL(string: "https://example.com/api/v1/test")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"hello":"world"}"#.utf8)

        let signed = try AKSKRequestSigner.authenticated(
            request,
            credentials: AKSKCredentials(accessKey: "ak", secretKey: "sk"),
            timestamp: 1,
            nonce: "nonce"
        )

        XCTAssertEqual(signed.value(forHTTPHeaderField: "X-API-Content-SHA256"), "93a23971a914e5eacbf0a8d25154cda309c3c1c72fbb9914d47c60f3cb681588")
    }
}
