import CryptoKit
import XCTest
@testable import MateDroidIOS

final class APIClientTests: XCTestCase {
    func testSettingsBackedFactoryLoadsAKSKSecrets() async throws {
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            secretStore: InMemoryAPISecretStore(values: [
                "apiAccessKey": " access-key ",
                "apiSecretKey": " secret-key "
            ])
        )

        switch await factory.makeAPI() {
        case let .success(api):
            XCTAssertEqual(api.authenticator.aksk, AKSKCredentials(accessKey: "access-key", secretKey: "secret-key"))
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testSettingsBackedFactoryLoadsCloudflareAccessSecrets() async throws {
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            secretStore: InMemoryAPISecretStore(values: [
                "apiToken": "token-123",
                "cloudflareAccessClientID": "cf-id",
                "cloudflareAccessClientSecret": "cf-secret"
            ])
        )

        switch await factory.makeAPI() {
        case let .success(api):
            XCTAssertEqual(api.authenticator.cloudflareAccess, CloudflareAccessAuth(clientID: "cf-id", clientSecret: "cf-secret"))
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testEndpointBuildsBearerAndSecondaryBasicAuthHeaders() throws {
        let endpoint = Endpoint(
            baseURL: URL(string: "https://example.com")!,
            path: "api/v1/cars",
            queryItems: [],
            bearerToken: "token-123",
            basicAuth: .init(username: "alice", password: "secret")
        )

        let request = try endpoint.request()

        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/cars")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MateDrive-Basic-Authorization"), "Basic YWxpY2U6c2VjcmV0")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-MateDroid-Basic-Authorization"))
    }

    func testEndpointUsesStandardAuthorizationHeaderForBasicAuthWithoutBearerToken() throws {
        let endpoint = Endpoint(
            baseURL: URL(string: "https://example.com")!,
            path: "api/v1/cars",
            basicAuth: .init(username: "alice", password: "secret")
        )

        let request = try endpoint.request()

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YWxpY2U6c2VjcmV0")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-MateDrive-Basic-Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-MateDroid-Basic-Authorization"))
    }

    func testCurrentChargeDecodingDistinguishesNoActiveCharge() throws {
        let data = #"{"error":"No active charge"}"#.data(using: .utf8)!
        let response = try JSONDecoder.teslamate.decode(ChargeDetailResponse.self, from: data)
        XCTAssertEqual(response.error, "No active charge")
        XCTAssertNil(response.data?.charge)
    }

    func testCurrentChargeTreatsNullDataAsNoActiveCharge() async throws {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://example.com")!,
            client: StubHTTPClient(json: #"{"data":null}"#)
        )

        switch await api.currentCharge(carId: 1) {
        case .success(.noActiveCharge):
            break
        case let .success(outcome):
            XCTFail("Expected no active charge, got \(outcome)")
        case let .failure(error):
            XCTFail("Expected no active charge, got \(error)")
        }
    }

    func testOptionalEndpointsTreatNullDataAsSuccessNil() async throws {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://example.com")!,
            client: StubHTTPClient(json: #"{"data":null}"#)
        )

        switch await api.battery(carId: 1) {
        case let .success(value):
            XCTAssertNil(value)
        case let .failure(error):
            XCTFail("Expected nil battery, got \(error)")
        }

        switch await api.globalSettings() {
        case let .success(value):
            XCTAssertNil(value)
        case let .failure(error):
            XCTFail("Expected nil settings, got \(error)")
        }
    }

    func testGlobalSettingsUsesTeslaMateGlobalSettingsEndpoint() async throws {
        let client = PathRecordingHTTPClient(json: #"{"data":{"settings":{"unit_of_length":"km"}}}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com")!, client: client)

        _ = await api.globalSettings()

        let requestedPaths = await client.requestedPaths
        XCTAssertEqual(requestedPaths, ["/api/v1/globalsettings"])
    }

    func testCostReviewUsesAPI26EndpointAndRFC3339RangeQuery() async throws {
        let client = URLRecordingHTTPClient(json: #"{"contractVersion":1,"data":{"range":{"startDate":"2026-07-01T00:00:00Z","endDate":"2026-07-08T00:00:00Z","period":"day"},"summary":{},"dataQuality":{"chargingCost":{},"parkingCost":{},"energyEstimate":{}},"buckets":[],"chargingModes":[],"placeRankings":{"charging":[],"parking":[],"standby":[]},"records":{"topCharges":[],"missingChargeCosts":[],"missingParkingCosts":[]}}}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com/base")!, client: client)
        let start = Date(timeIntervalSince1970: 1_751_328_000)
        let end = Date(timeIntervalSince1970: 1_751_932_800)

        _ = await api.costReview(carId: 7, startDate: start, endDate: end)

        let requestedURL = await client.requestedURL
        let url = try XCTUnwrap(requestedURL)
        XCTAssertEqual(url.path, "/base/api/v1/cars/7/stats/cost-charging-detail")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.map(\.name), ["start_date", "end_date"])
        XCTAssertEqual(query.map(\.value), ["2025-07-01T00:00:00Z", "2025-07-08T00:00:00Z"])
    }

    func testVehicleStateHistoryUsesOptionalEndpointAndBoundedQuery() async throws {
        let client = URLRecordingHTTPClient(json: #"{"data":{"states":[]}}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com/base")!, client: client)

        let result = await api.vehicleStateHistory(
            carId: 7,
            startDate: "2026-07-16T00:00:00Z",
            endDate: "2026-07-17T00:00:00Z"
        )

        guard case let .success(intervals) = result else {
            return XCTFail("Expected state history response")
        }
        XCTAssertTrue(intervals.isEmpty)

        let requestedURL = try XCTUnwrap(await client.requestedURL)
        XCTAssertEqual(requestedURL.path, "/base/api/v1/cars/7/states")
        let query = try XCTUnwrap(URLComponents(url: requestedURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.map(\.name), ["startDate", "endDate"])
        XCTAssertEqual(query.map(\.value), ["2026-07-16T00:00:00Z", "2026-07-17T00:00:00Z"])
    }

    func testUpdateChargeCostUsesAPI26PutEndpointAndNumericJSONBody() async throws {
        let client = RequestRecordingHTTPClient(json: #"{"message":"updated"}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com/base")!, client: client)

        switch await api.updateChargeCost(chargeId: 42, cost: 12.34) {
        case .success:
            break
        case let .failure(error):
            XCTFail("Expected charge cost update, got \(error)")
        }

        let recordedRequest = await client.recordedRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url.path, "/base/api/v1/charging-processes/42/cost")
        XCTAssertEqual(request.contentType, "application/json")
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["cost"] as? Double, 12.34)
    }

    func testUpdateChargeCostEncodesClearAsExplicitJSONNull() async throws {
        let client = RequestRecordingHTTPClient(json: #"{"message":"updated"}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com")!, client: client)

        _ = await api.updateChargeCost(chargeId: 42, cost: nil)

        let recordedRequest = await client.recordedRequest
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json["cost"] is NSNull)
    }

    func testUpdateChargeCostSignsFinalPutMethodAndBodyForAKSK() async throws {
        let client = RequestRecordingHTTPClient(json: #"{"message":"updated"}"#)
        let api = TeslamateAPI(
            baseURL: URL(string: "https://example.com")!,
            aksk: AKSKCredentials(accessKey: "access-key", secretKey: "secret-key"),
            client: client
        )

        _ = await api.updateChargeCost(chargeId: 42, cost: 12.34)

        let recordedRequest = await client.recordedRequest
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.body)
        let expectedBodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.contentHash, expectedBodyHash)
    }

    func testUpdateChargeCostConvertsHTTP200BusinessErrorIntoFailure() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://example.com")!,
            client: RequestRecordingHTTPClient(json: #"{"error":"Charging process not found"}"#)
        )

        switch await api.updateChargeCost(chargeId: 999_999_999, cost: 12.34) {
        case .success:
            XCTFail("Expected business error")
        case let .failure(error):
            XCTAssertEqual(error, APIError.invalidResponse("Charging process not found"))
        }
    }

    func testSettingsBackedFactoryAppliesInvalidCertificatePreference() async throws {
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(serverURL: " https://teslamate.example ", acceptInvalidCerts: true)
        )
        let secretStore = InMemoryAPISecretStore(values: [
            "apiToken": " token-123 ",
            "httpBasicAuthUsername": " alice ",
            "httpBasicAuthPassword": " secret "
        ])
        let factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)

        switch await factory.makeAPI() {
        case let .success(api):
            XCTAssertEqual(api.baseURL.absoluteString, "https://teslamate.example")
            XCTAssertEqual(api.bearerToken, "token-123")
            XCTAssertEqual(api.basicAuth, BasicAuth(username: "alice", password: "secret"))
            let client = try XCTUnwrap(api.client as? URLSessionHTTPClient)
            XCTAssertTrue(client.acceptsInvalidCertificates)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testSettingsBackedFactoryKeepsCertificateValidationByDefaultAndIgnoresBlankBasicAuth() async throws {
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example", acceptInvalidCerts: false)
        )
        let secretStore = InMemoryAPISecretStore(values: [
            "apiToken": "token-123",
            "httpBasicAuthUsername": " ",
            "httpBasicAuthPassword": "secret"
        ])
        let factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)

        switch await factory.makeAPI() {
        case let .success(api):
            XCTAssertEqual(api.bearerToken, "token-123")
            XCTAssertNil(api.basicAuth)
            let client = try XCTUnwrap(api.client as? URLSessionHTTPClient)
            XCTAssertFalse(client.acceptsInvalidCertificates)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testSettingsBackedFactoryFallsBackToSecondaryServerForRetryableFailures() async throws {
        let client = HostRoutingHTTPClient(routes: [
            "primary.example": .failure(.network("offline")),
            "backup.example": .success(#"{"data":{"cars":[{"car_id":1,"display_name":"Backup"}]}}"#)
        ])
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(
                serverURL: "https://primary.example",
                secondaryServerURL: "https://backup.example"
            )
        )
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: InMemoryAPISecretStore(values: [:]),
            clientOverride: client
        )

        switch await factory.request({ api in await api.cars() }) {
        case let .success(cars):
            XCTAssertEqual(cars.map(\.displayName), ["Backup"])
        case let .failure(error):
            XCTFail("Expected fallback cars, got \(error)")
        }
        let requestedHosts = await client.requestedHosts()
        XCTAssertEqual(requestedHosts, ["primary.example", "backup.example"])
    }

    func testSettingsBackedFactoryDoesNotFallbackForAuthenticationFailures() async throws {
        let client = HostRoutingHTTPClient(routes: [
            "primary.example": .httpStatus(401),
            "backup.example": .success(#"{"data":{"cars":[{"car_id":1,"display_name":"Backup"}]}}"#)
        ])
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(
                serverURL: "https://primary.example",
                secondaryServerURL: "https://backup.example"
            )
        )
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: InMemoryAPISecretStore(values: [:]),
            clientOverride: client
        )

        switch await factory.request({ api in await api.cars() }) {
        case .success:
            XCTFail("Expected 401 failure")
        case let .failure(error):
            XCTAssertEqual(error, .httpStatus(401))
        }
        let requestedHosts = await client.requestedHosts()
        XCTAssertEqual(requestedHosts, ["primary.example"])
    }
}

private struct StubHTTPClient: HTTPClient {
    let json: String
    let statusCode: Int

    init(json: String, statusCode: Int = 200) {
        self.json = json
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
}

private actor PathRecorder {
    private var paths: [String] = []

    var requestedPaths: [String] {
        paths
    }

    func append(_ path: String) {
        paths.append(path)
    }
}

private struct PathRecordingHTTPClient: HTTPClient {
    let json: String
    private let recorder = PathRecorder()

    var requestedPaths: [String] {
        get async { await recorder.requestedPaths }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        await recorder.append(url.path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
}

private actor URLRecorder {
    private(set) var url: URL?
    func record(_ url: URL?) { self.url = url }
}

private struct URLRecordingHTTPClient: HTTPClient {
    let json: String
    private let recorder = URLRecorder()

    var requestedURL: URL? {
        get async { await recorder.url }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        await recorder.record(url)
        return (
            Data(json.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private struct RecordedHTTPRequest: Sendable {
    let url: URL
    let method: String?
    let contentType: String?
    let body: Data?
    let contentHash: String?
}

private actor RequestRecorder {
    private(set) var request: RecordedHTTPRequest?

    func record(_ request: URLRequest) {
        self.request = RecordedHTTPRequest(
            url: request.url ?? URL(string: "https://example.com")!,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: request.httpBody,
            contentHash: request.value(forHTTPHeaderField: "X-API-Content-SHA256")
        )
    }
}

private struct RequestRecordingHTTPClient: HTTPClient {
    let json: String
    let statusCode: Int
    private let recorder = RequestRecorder()

    init(json: String, statusCode: Int = 200) {
        self.json = json
        self.statusCode = statusCode
    }

    var recordedRequest: RecordedHTTPRequest? {
        get async { await recorder.request }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await recorder.record(request)
        let url = request.url ?? URL(string: "https://example.com")!
        return (
            Data(json.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private final class HostRoutingHTTPClient: HTTPClient, @unchecked Sendable {
    enum Route: Sendable {
        case success(String)
        case failure(APIError)
        case httpStatus(Int)
    }

    private let routes: [String: Route]
    private let requestRecorder = HostRequestRecorder()

    func requestedHosts() async -> [String] {
        await requestRecorder.hosts
    }

    init(routes: [String: Route]) {
        self.routes = routes
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://missing.example")!
        let host = url.host ?? ""
        await requestRecorder.append(host)

        switch routes[host] ?? .failure(.network("No route for \(host)")) {
        case let .success(json):
            return (Data(json.utf8), httpResponse(url: url, statusCode: 200))
        case let .failure(error):
            throw error
        case let .httpStatus(statusCode):
            return (Data("{}".utf8), httpResponse(url: url, statusCode: statusCode))
        }
    }

    private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}

private actor HostRequestRecorder {
    private var requestedHosts: [String] = []

    var hosts: [String] {
        requestedHosts
    }

    func append(_ host: String) {
        requestedHosts.append(host)
    }
}

private final class InMemoryAPISettingsStore: SettingsStoring, @unchecked Sendable {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_: AppSettings) async {}
}

private final class InMemoryAPISecretStore: SecretStoring, @unchecked Sendable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    func get(_ key: String) async throws -> String? {
        values[key]
    }

    func set(_: String, for _: String) async throws {}

    func remove(_: String) async throws {}
}
