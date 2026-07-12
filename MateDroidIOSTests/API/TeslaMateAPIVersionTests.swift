import Foundation
import XCTest
@testable import MateDroidIOS

final class TeslaMateAPIVersionTests: XCTestCase {
    func testSemanticVersionAcceptsPrefixAndMissingPatch() {
        XCTAssertEqual(TeslaMateAPIVersion("v2.5"), TeslaMateAPIVersion(major: 2, minor: 5, patch: 0))
        XCTAssertEqual(TeslaMateAPIVersion("2.4.1"), TeslaMateAPIVersion(major: 2, minor: 4, patch: 1))
        XCTAssertEqual(TeslaMateAPIVersion("2.5.0-beta.1"), TeslaMateAPIVersion(major: 2, minor: 5, patch: 0))
        XCTAssertNil(TeslaMateAPIVersion("unknown"))
        XCTAssertNil(TeslaMateAPIVersion("2"))
    }

    func testSemanticVersionRejectsEmptyPrereleaseSuffix() {
        XCTAssertNil(TeslaMateAPIVersion("2.5-"))
    }

    func testVersionInfoPrefersMTAPIVersion() {
        let info = TeslaMateVersionInfo(
            apiVersion: "9.0.0",
            mtAPIVersion: "2.4.1",
            buildInfo: "TeslaMate API"
        )

        XCTAssertEqual(info.resolvedVersion, TeslaMateAPIVersion(major: 2, minor: 4, patch: 1))
        XCTAssertEqual(info.displayVersion, "2.4.1")
    }

    func testVersionEndpointDecodesDirectPayload() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://teslamate.example")!,
            client: VersionHTTPClient(statusCode: 200, json: #"{"api_version":"unknown","build_info":"TeslaMate API","mt_api_version":"2.4.1"}"#)
        )

        switch await api.version() {
        case let .success(info):
            XCTAssertEqual(info.mtAPIVersion, "2.4.1")
            XCTAssertEqual(info.resolvedVersion, TeslaMateAPIVersion(major: 2, minor: 4, patch: 1))
        case let .failure(error):
            XCTFail("Expected version success, got \(error)")
        }
    }
}

private struct VersionHTTPClient: HTTPClient {
    let statusCode: Int
    let json: String

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
}
