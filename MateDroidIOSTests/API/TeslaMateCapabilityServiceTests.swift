import Foundation
import XCTest
@testable import MateDroidIOS

final class TeslaMateCapabilityServiceTests: XCTestCase {
    func testDiscoveryUsesEndpointEvidenceAndFlagsBrokenActivityPagination() async {
        let client = CapabilityRouteHTTPClient(routes: [
            "/api/v1/version": (200, #"{"api_version":"unknown","mt_api_version":"2.4.1","build_info":"TeslaMate API"}"#),
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{}}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, ""),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{}}}"#),
            "/api/v1/cars/1/stats": (200, #"{"data":{"summary":{"totalDistanceKm":1010}}}"#),
            "/api/v1/cars/1/stats/cost-charging-detail": (200, #"{"contractVersion":1,"data":{"summary":{}}}"#),
            "/api/v1/cars/1/activities": (200, #"{"data":{"activities":[{"id":1,"type":"drive"}],"totalRecords":0,"totalPages":9999}}"#),
            "/api/v1/cars/1/battery-health/history": (200, #"{"data":{"capacity":[]}}"#),
            "/api/v1/cars/1/drive-stats": (200, #"{"data":{"routes":[]}}"#),
            "/api/v1/cars/1/environment-history": (200, #"{"data":{"series":[]}}"#),
            "/api/v1/cars/1/states": (404, #"{"error":"not found"}"#),
            "/api/v1/cars/1/achievements": (404, #"{"error":"not found"}"#),
            "/api/v1/geofences": (500, #"{"error":"temporary"}"#),
            "/api/v1/cars/1/top-drain-locations": (200, #"{"locations":[]}"#),
            "/api/v1/cars/1/commute-routes": (200, #"{"routes":[]}"#),
            "/api/v1/cars/1/stats/extremes": (200, #"{"extremes":[]}"#),
            "/api/v1/cars/1/driving-coordinates": (200, #"{"data":{"coordinates":[]}}"#),
            "/api/v1/cars/1/places": (200, #"{"data":[]}"#)
        ])
        let service = TeslaMateCapabilityService(
            profileStore: EmptyTeslaMateServerProfileStore(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let profile = await service.discover(api: api, carId: 1, force: true)

        XCTAssertEqual(profile.version.displayVersion, "2.4.1")
        XCTAssertEqual(profile.status(for: .serverStats)?.state, .available)
        XCTAssertEqual(profile.status(for: .costReview)?.state, .available)
        XCTAssertEqual(profile.status(for: .unifiedActivities)?.state, .degraded)
        XCTAssertEqual(profile.status(for: .unifiedActivities)?.reason, .paginationMetadataInvalid)
        XCTAssertEqual(profile.status(for: .environmentHistory)?.state, .available)
        XCTAssertEqual(profile.status(for: .stateHistory)?.state, .unavailable)
        XCTAssertEqual(profile.status(for: .stateHistory)?.reason, .endpointNotFound)
        XCTAssertEqual(profile.status(for: .topDrainLocations)?.state, .available)
        XCTAssertEqual(profile.status(for: .commuteRoutes)?.state, .available)
        XCTAssertEqual(profile.status(for: .statsExtremes)?.state, .available)
        XCTAssertEqual(profile.status(for: .drivingCoordinates)?.state, .available)
        XCTAssertEqual(profile.status(for: .serverPlaces)?.state, .available)
        XCTAssertEqual(profile.status(for: .achievements)?.state, .unavailable)
        XCTAssertEqual(profile.status(for: .geofences)?.state, .unknown)
        XCTAssertEqual(profile.status(for: .chargeDetail)?.reason, .notProbed)
        XCTAssertEqual(profile.status(for: .standbyDrain)?.reason, .parametersRequired)
    }

    func testDiscoveryReusesProfileYoungerThan24HoursUnlessForced() async throws {
        let store = RecordingTeslaMateServerProfileStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cached = TeslaMateServerProfile(
            serverKey: TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example")!),
            carId: 1,
            version: TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: "2.4.1", buildInfo: nil),
            capabilities: [:],
            checkedAt: now.addingTimeInterval(-60),
            lastSuccessfulCheckAt: now.addingTimeInterval(-60)
        )
        await store.seed(cached)
        let client = CapabilityRouteHTTPClient(routes: [:])
        let service = TeslaMateCapabilityService(profileStore: store, now: { now })
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let loaded = await service.discover(api: api, carId: 1, force: false)

        XCTAssertEqual(loaded, cached)
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testCapabilityCatalogContainsCoreAndEnhancedFeatures() {
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.coreCars))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.serverStats))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.costReview))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.unifiedActivities))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.batteryHealthHistory))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.driveInsights))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.environmentHistory))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.stateHistory))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.standbyDrain))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.topDrainLocations))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.commuteRoutes))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.statsExtremes))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.drivingCoordinates))
        XCTAssertTrue(TeslaMateCapability.allCases.contains(.serverPlaces))
    }

    func testStateHistoryProbeUsesOneDayRangeAndOnlyEndpointAbsenceIsUnavailable() async throws {
        let now = Date(timeIntervalSince1970: 1_784_246_400)
        let cases: [(Int, TeslaMateCapabilityState, TeslaMateCapabilityReason)] = [
            (404, .unavailable, .endpointNotFound),
            (405, .unavailable, .methodNotAllowed),
            (400, .unknown, .invalidPayload),
            (401, .unknown, .authenticationRequired),
            (500, .unknown, .temporaryServerFailure)
        ]

        for (statusCode, expectedState, expectedReason) in cases {
            let client = StateHistoryCapabilityHTTPClient(statusCode: statusCode)
            let service = TeslaMateCapabilityService(now: { now })
            let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

            let profile = await service.discover(api: api, carId: 1, force: true)

            XCTAssertEqual(profile.status(for: .stateHistory)?.state, expectedState, "HTTP \(statusCode)")
            XCTAssertEqual(profile.status(for: .stateHistory)?.reason, expectedReason, "HTTP \(statusCode)")
            let recordedRequest = await client.stateHistoryRequest
            let request = try XCTUnwrap(recordedRequest, "HTTP \(statusCode)")
            let query = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.map(\.name), ["startDate", "endDate"])
            XCTAssertEqual(query.map(\.value), ["2026-07-16T00:00:00Z", "2026-07-17T00:00:00Z"])
        }
    }

    func testGenericHTTPFailureStillDegradesOtherCapabilities() async {
        let client = CapabilityRouteHTTPClient(routes: [
            "/api/v1/cars/1/status": (400, #"{"error":"bad request"}"#)
        ])
        let service = TeslaMateCapabilityService()
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let profile = await service.discover(api: api, carId: 1, force: true)

        XCTAssertEqual(profile.status(for: .vehicleStatus)?.state, .degraded)
        XCTAssertEqual(profile.status(for: .vehicleStatus)?.reason, .invalidPayload)
    }

    func testStateHistorySuccessfulEmptyOrMalformedPayloadIsUnknown() async {
        let cases: [(String, TeslaMateCapabilityReason)] = [
            ("", .emptyPayload),
            ("not-json", .invalidPayload)
        ]

        for (body, expectedReason) in cases {
            let client = StateHistoryCapabilityHTTPClient(statusCode: 200, body: body)
            let service = TeslaMateCapabilityService()
            let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

            let profile = await service.discover(api: api, carId: 1, force: true)

            XCTAssertEqual(profile.status(for: .stateHistory)?.state, .unknown, "Body: \(body)")
            XCTAssertEqual(profile.status(for: .stateHistory)?.reason, expectedReason, "Body: \(body)")
        }
    }

    func testStateHistoryInvalidObjectShapesAreUnknown() async {
        for body in [#"{}"#, #"{"data":{}}"#] {
            let client = StateHistoryCapabilityHTTPClient(statusCode: 200, body: body)
            let service = TeslaMateCapabilityService()
            let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

            let profile = await service.discover(api: api, carId: 1, force: true)

            XCTAssertEqual(profile.status(for: .stateHistory)?.state, .unknown, "Body: \(body)")
            XCTAssertEqual(profile.status(for: .stateHistory)?.reason, .invalidPayload, "Body: \(body)")
        }
    }

    func testStateHistoryValidEmptyShapesAreAvailable() async {
        for body in [#"[]"#, #"{"data":{"states":[]}}"#] {
            let client = StateHistoryCapabilityHTTPClient(statusCode: 200, body: body)
            let service = TeslaMateCapabilityService()
            let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

            let profile = await service.discover(api: api, carId: 1, force: true)

            XCTAssertEqual(profile.status(for: .stateHistory)?.state, .available, "Body: \(body)")
            XCTAssertNil(profile.status(for: .stateHistory)?.reason, "Body: \(body)")
        }
    }

    func testSuccessfulEmptyPayloadStillDegradesOtherCapabilities() async {
        let client = CapabilityRouteHTTPClient(routes: [
            "/api/v1/cars/1/status": (200, "")
        ])
        let service = TeslaMateCapabilityService()
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let profile = await service.discover(api: api, carId: 1, force: true)

        XCTAssertEqual(profile.status(for: .vehicleStatus)?.state, .degraded)
        XCTAssertEqual(profile.status(for: .vehicleStatus)?.reason, .emptyPayload)
    }

    func testStateHistoryNoContentIsUnknownRegardlessOfBody() async {
        let client = StateHistoryCapabilityHTTPClient(statusCode: 204, body: #"{"data":{"states":[]}}"#)
        let service = TeslaMateCapabilityService()
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let profile = await service.discover(api: api, carId: 1, force: true)

        XCTAssertEqual(profile.status(for: .stateHistory)?.state, .unknown)
        XCTAssertEqual(profile.status(for: .stateHistory)?.reason, .emptyPayload)
    }

    func testNoContentRemainsAvailableForOtherCapabilities() async {
        let client = CapabilityRouteHTTPClient(routes: [
            "/api/v1/cars/1/status": (204, "")
        ])
        let service = TeslaMateCapabilityService()
        let api = TeslamateAPI(baseURL: URL(string: "https://teslamate.example")!, client: client)

        let profile = await service.discover(api: api, carId: 1, force: true)

        XCTAssertEqual(profile.status(for: .vehicleStatus)?.state, .available)
        XCTAssertNil(profile.status(for: .vehicleStatus)?.reason)
    }

    func testServerIdentityExcludesCredentialsQueryAndFragmentAndNormalizesEquivalentURLs() {
        let credentialed = TeslaMateServerIdentity.key(for: makeCredentialedURL(
            scheme: "HTTPS", user: "alice", password: "secret", host: "TeslaMate.Example", port: 443,
            path: "/base/path/", query: "token=private", fragment: "details"
        ))
        let differentCredentials = TeslaMateServerIdentity.key(for: makeCredentialedURL(
            scheme: "https", user: "bob", password: "other", host: "teslamate.example",
            path: "/base/path", query: "session=other", fragment: "different"
        ))
        let canonical = TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example/base/path")!)
        let httpDefaultPort = TeslaMateServerIdentity.key(for: URL(string: "http://TeslaMate.Example:80/")!)
        let httpCanonical = TeslaMateServerIdentity.key(for: URL(string: "http://teslamate.example")!)

        XCTAssertEqual(credentialed, canonical)
        XCTAssertEqual(differentCredentials, canonical)
        XCTAssertEqual(httpDefaultPort, httpCanonical)
    }

    private func makeCredentialedURL(
        scheme: String,
        user: String,
        password: String,
        host: String,
        port: Int? = nil,
        path: String,
        query: String,
        fragment: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.user = user
        components.password = password
        components.host = host
        components.port = port
        components.path = path
        components.query = query
        components.fragment = fragment
        return components.url!
    }

    func testServerIdentityPreservesMeaningfulBasePaths() {
        let root = TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example/")!)
        let basePath = TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example/teslamate/")!)
        let nestedBasePath = TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example/teslamate/v2/")!)
        let normalizedBasePath = TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example/teslamate")!)

        XCTAssertEqual(basePath, normalizedBasePath)
        XCTAssertNotEqual(root, basePath)
        XCTAssertNotEqual(basePath, nestedBasePath)
    }

    func testRawProbeUsesGETAndPassesThroughAuthenticationAndQueryItems() async {
        let client = CapturingHTTPClient(statusCode: 200, data: Data("payload".utf8))
        let api = TeslamateAPI(
            baseURL: URL(string: "https://teslamate.example/base")!,
            bearerToken: "token-123",
            basicAuth: BasicAuth(username: "alice", password: "secret"),
            cloudflareAccess: CloudflareAccessAuth(clientID: "cf-id", clientSecret: "cf-secret"),
            client: client
        )

        let result = await api.probe(
            path: "api/v1/cars",
            queryItems: [
                URLQueryItem(name: "page", value: "2"),
                URLQueryItem(name: "include", value: "status")
            ]
        )

        guard case .success = result else {
            return XCTFail("Expected probe success, got \(result)")
        }
        let request = try! XCTUnwrap(client.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MateDrive-Basic-Authorization"), "Basic YWxpY2U6c2VjcmV0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "cf-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "cf-secret")
        XCTAssertEqual(URLComponents(url: try! XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "page", value: "2"),
            URLQueryItem(name: "include", value: "status")
        ])
    }

    func testRawProbeReturnsHTTPStatusForNon2xxResponses() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://teslamate.example")!,
            client: CapturingHTTPClient(statusCode: 503, data: Data("unavailable".utf8))
        )

        guard case let .failure(error) = await api.probe(path: "api/v1/cars") else {
            return XCTFail("Expected probe failure")
        }
        XCTAssertEqual(error, .httpStatus(503))
    }

    func testRawProbeMapsTransportErrorsToNetworkErrors() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://teslamate.example")!,
            client: FailingHTTPClient()
        )

        guard case let .failure(error) = await api.probe(path: "api/v1/cars") else {
            return XCTFail("Expected probe failure")
        }
        XCTAssertEqual(error, .network("offline"))
    }

    func testRawProbePreservesSuccessfulStatusAndEmptyBody() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://teslamate.example")!,
            client: CapturingHTTPClient(statusCode: 204, data: Data())
        )

        guard case let .success(response) = await api.probe(path: "api/v1/cars/1/stats") else {
            return XCTFail("Expected probe success")
        }
        XCTAssertEqual(response, TeslaMateProbeResponse(statusCode: 204, data: Data()))
    }

    func testServerProfileCodableRoundTripsAllCapabilityStatesAndConnectionIssues() throws {
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastSuccessfulAt = Date(timeIntervalSince1970: 1_700_000_100)
        let capabilities: [TeslaMateCapability: TeslaMateCapabilityStatus] = [
            .coreCars: TeslaMateCapabilityStatus(state: .available, source: .endpointProbe, checkedAt: checkedAt, lastSuccessfulAt: lastSuccessfulAt),
            .serverStats: TeslaMateCapabilityStatus(state: .degraded, reason: .invalidPayload, source: .endpointProbe, checkedAt: checkedAt),
            .driveInsights: TeslaMateCapabilityStatus(state: .unavailable, reason: .endpointNotFound, source: .legacyDiagnostic, checkedAt: checkedAt),
            .standbyDrain: TeslaMateCapabilityStatus(state: .unknown, reason: .notProbed, source: .cached, checkedAt: checkedAt)
        ]
        let issues: [TeslaMateConnectionIssue?] = [
            .authentication(statusCode: 401),
            .temporaryServerFailure(statusCode: 503),
            .network
        ]

        for issue in issues {
            let profile = TeslaMateServerProfile(
                serverKey: "server-key",
                carId: 7,
                version: TeslaMateVersionInfo(apiVersion: "1.0.0", mtAPIVersion: "2.4.1", buildInfo: "test"),
                capabilities: capabilities,
                connectionIssue: issue,
                checkedAt: checkedAt,
                lastSuccessfulCheckAt: lastSuccessfulAt
            )

            let decoded = try JSONDecoder().decode(TeslaMateServerProfile.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(decoded, profile)
        }
    }
}

private actor CapabilityRequestCounter {
    private var count = 0
    func increment() { count += 1 }
    var value: Int { count }
}

private final class CapabilityRouteHTTPClient: HTTPClient, @unchecked Sendable {
    let routes: [String: (Int, String)]
    private let counter = CapabilityRequestCounter()

    init(routes: [String: (Int, String)]) {
        self.routes = routes
    }

    var requestCount: Int {
        get async { await counter.value }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await counter.increment()
        let path = request.url?.path ?? ""
        let route = routes[path] ?? (404, #"{"error":"not found"}"#)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: route.0,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(route.1.utf8), response)
    }
}

private actor StateHistoryRequestRecorder {
    private(set) var request: URLRequest?
    func record(_ request: URLRequest) { self.request = request }
}

private struct StateHistoryCapabilityHTTPClient: HTTPClient {
    let statusCode: Int
    let body: String
    private let recorder = StateHistoryRequestRecorder()

    init(statusCode: Int, body: String = "{}") {
        self.statusCode = statusCode
        self.body = body
    }

    var stateHistoryRequest: URLRequest? {
        get async { await recorder.request }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isStateHistory = request.url?.path == "/api/v1/cars/1/states"
        if isStateHistory {
            await recorder.record(request)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: isStateHistory ? statusCode : 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

private actor RecordingTeslaMateServerProfileStore: TeslaMateServerProfileStoring {
    private var value: TeslaMateServerProfile?
    func seed(_ profile: TeslaMateServerProfile) { value = profile }
    func profile(serverKey: String, carId: Int) async throws -> TeslaMateServerProfile? {
        value?.serverKey == serverKey && value?.carId == carId ? value : nil
    }
    func save(_ profile: TeslaMateServerProfile) async throws { value = profile }
    func delete(serverKey: String) async throws {
        if value?.serverKey == serverKey { value = nil }
    }
}

private final class CapturingHTTPClient: HTTPClient, @unchecked Sendable {
    let statusCode: Int
    let data: Data
    private(set) var request: URLRequest?

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct FailingHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw TestNetworkError.offline
    }
}

private enum TestNetworkError: LocalizedError {
    case offline

    var errorDescription: String? {
        "offline"
    }
}
