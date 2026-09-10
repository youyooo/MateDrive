import CryptoKit
import XCTest
@testable import MateDriveApp

final class APIClientTests: XCTestCase {
    func testCachedHTTPClientReusesFreshGETResponse() async throws {
        let upstream = CountingHTTPClient()
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/drives")!)

        _ = try await client.data(for: request)
        _ = try await client.data(for: request)
        let requestCount = await upstream.requestCount

        XCTAssertEqual(requestCount, 1)
    }

    func testCachedHTTPClientReusesResponseAcrossRotatingAKSKSignatureHeaders() async throws {
        let upstream = CountingHTTPClient()
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        let url = URL(string: "https://example.com/api/v1/cars/1/status")!
        var first = URLRequest(url: url)
        first.setValue("access-key", forHTTPHeaderField: "X-API-Access-Key")
        first.setValue("100", forHTTPHeaderField: "X-API-Timestamp")
        first.setValue("nonce-1", forHTTPHeaderField: "X-API-Nonce")
        first.setValue("signature-1", forHTTPHeaderField: "X-API-Signature")
        var second = URLRequest(url: url)
        second.setValue("access-key", forHTTPHeaderField: "X-API-Access-Key")
        second.setValue("101", forHTTPHeaderField: "X-API-Timestamp")
        second.setValue("nonce-2", forHTTPHeaderField: "X-API-Nonce")
        second.setValue("signature-2", forHTTPHeaderField: "X-API-Signature")

        _ = try await client.data(for: first)
        _ = try await client.data(for: second)

        let requestCount = await upstream.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testCachedHTTPClientKeepsDifferentAKSKAccountsIsolated() async throws {
        let upstream = CountingHTTPClient()
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        let url = URL(string: "https://example.com/api/v1/cars/1/status")!
        var first = URLRequest(url: url)
        first.setValue("access-key-a", forHTTPHeaderField: "X-API-Access-Key")
        var second = URLRequest(url: url)
        second.setValue("access-key-b", forHTTPHeaderField: "X-API-Access-Key")

        _ = try await client.data(for: first)
        _ = try await client.data(for: second)

        let requestCount = await upstream.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testCachedHTTPClientCoalescesConcurrentGETRequests() async throws {
        let upstream = CountingHTTPClient(delay: .milliseconds(100))
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/charges")!)

        async let first = client.data(for: request)
        async let second = client.data(for: request)
        _ = try await (first, second)
        let requestCount = await upstream.requestCount

        XCTAssertEqual(requestCount, 1)
    }

    func testCachedHTTPClientReloadPolicyRefreshesStoredResponse() async throws {
        let upstream = CountingHTTPClient()
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        let url = URL(string: "https://example.com/api/v1/cars/1/status")!
        let regularRequest = URLRequest(url: url)
        var reloadRequest = URLRequest(url: url)
        reloadRequest.cachePolicy = .reloadIgnoringLocalCacheData

        _ = try await client.data(for: regularRequest)
        _ = try await client.data(for: reloadRequest)
        _ = try await client.data(for: regularRequest)
        let requestCount = await upstream.requestCount

        XCTAssertEqual(requestCount, 2)
    }

    func testCacheOnlyRequestNeverUsesUpstreamWhenResponseIsMissing() async {
        let upstream = CountingHTTPClient()
        let client = CachedHTTPClient(
            upstream: upstream,
            cache: HTTPResponseCache(refreshAfter: 60)
        )
        var request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/drives/404")!)
        request.cachePolicy = .returnCacheDataDontLoad

        do {
            _ = try await client.data(for: request)
            XCTFail("Expected a cache miss")
        } catch {
            // A cache-only page read must fail locally instead of reaching the server.
        }

        let requestCount = await upstream.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testCacheOnlyRequestReturnsExpiredResponseWithoutRefreshingUpstream() async throws {
        let now = LockedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let upstream = CountingHTTPClient()
        let cache = HTTPResponseCache(
            refreshAfter: 1,
            maximumAge: 2,
            now: { now.value }
        )
        let client = CachedHTTPClient(upstream: upstream, cache: cache)
        let url = URL(string: "https://example.com/api/v1/cars/1/drives/1")!

        _ = try await client.data(for: URLRequest(url: url))
        now.advance(by: 24 * 60 * 60)
        var cacheOnlyRequest = URLRequest(url: url)
        cacheOnlyRequest.cachePolicy = .returnCacheDataDontLoad
        _ = try await client.data(for: cacheOnlyRequest)

        let requestCount = await upstream.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testCacheOnlyNetworkPolicyMarksReadsAsCacheOnly() async throws {
        let upstream = RequestRecordingHTTPClient(json: #"{"data":{}}"#)
        let client = NetworkPolicyHTTPClient(upstream: upstream, policy: .cacheOnly)

        _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/status")!))

        let recordedRequest = await upstream.recordedRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.cachePolicy, .returnCacheDataDontLoad)
    }

    func testCacheOnlyNetworkPolicyDoesNotBlockMutations() async throws {
        let upstream = RequestRecordingHTTPClient(json: #"{"message":"updated"}"#)
        let client = NetworkPolicyHTTPClient(upstream: upstream, policy: .cacheOnly)
        var request = URLRequest(url: URL(string: "https://example.com/api/v1/charges/1/cost")!)
        request.httpMethod = "PUT"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        _ = try await client.data(for: request)

        let recordedRequest = await upstream.recordedRequest
        let recorded = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(recorded.method, "PUT")
        XCTAssertEqual(recorded.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testCachedHTTPClientRestoresResponseFromProtectedDiskCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://example.com/api/v1/cars/1/drives?page=1&show=50000")!
        let request = URLRequest(url: url)
        let firstUpstream = CountingHTTPClient()
        let firstCache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )

        _ = try await CachedHTTPClient(upstream: firstUpstream, cache: firstCache).data(for: request)

        let secondUpstream = CountingHTTPClient()
        let restoredCache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )
        _ = try await CachedHTTPClient(upstream: secondUpstream, cache: restoredCache).data(for: request)
        let secondRequestCount = await secondUpstream.requestCount
        let statistics = await restoredCache.statistics()

        XCTAssertEqual(secondRequestCount, 0)
        XCTAssertEqual(statistics.recordCount, 1)
        XCTAssertGreaterThan(statistics.byteCount, 0)
    }

    func testCachedHTTPClientRestoresDayOldDiskResponseBeforeBackgroundRefreshCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCacheOffline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = LockedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/activities?page=1&show=20")!)
        let firstCache = HTTPResponseCache(
            diskStore: FileHTTPResponseDiskStore(directory: directory),
            now: { now.value }
        )
        _ = try await CachedHTTPClient(upstream: CountingHTTPClient(), cache: firstCache).data(for: request)
        now.advance(by: 24 * 60 * 60)

        let refreshGate = AsyncRequestGate()
        let refreshClient = GatedHTTPClient(gate: refreshGate)
        let restoredCache = HTTPResponseCache(
            diskStore: FileHTTPResponseDiskStore(directory: directory),
            now: { now.value }
        )
        let completion = CompletionFlag()
        let restoredRequest = Task {
            _ = try await CachedHTTPClient(upstream: refreshClient, cache: restoredCache).data(for: request)
            await completion.markCompleted()
        }

        try await Task.sleep(for: .milliseconds(100))
        let completedBeforeRefresh = await completion.isCompleted
        await refreshGate.open()
        _ = try await restoredRequest.value
        let refreshRequestCount = await refreshClient.requestCount

        XCTAssertTrue(completedBeforeRefresh)
        XCTAssertEqual(refreshRequestCount, 1)
    }

    func testHTTPResponseCacheStatisticsIncludeStoredDateRange() async throws {
        let now = LockedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let cache = HTTPResponseCache(refreshAfter: 60, now: { now.value })
        let client = CachedHTTPClient(upstream: CountingHTTPClient(), cache: cache)

        _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/api/v1/cars")!))
        now.advance(by: 60)
        _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/api/v1/globalsettings")!))
        let statistics = await cache.statistics()

        XCTAssertEqual(statistics.oldestStoredAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(statistics.newestStoredAt, Date(timeIntervalSince1970: 1_700_000_060))
    }

    func testHTTPResponseCacheRemoveAllClearsPersistentResponses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCacheClear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diskStore = FileHTTPResponseDiskStore(directory: directory)
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/charges?page=1&show=50000")!)
        let firstUpstream = CountingHTTPClient()
        let firstCache = HTTPResponseCache(refreshAfter: 60, diskStore: diskStore)
        _ = try await CachedHTTPClient(upstream: firstUpstream, cache: firstCache).data(for: request)

        await firstCache.removeAll()

        let secondUpstream = CountingHTTPClient()
        let secondCache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )
        _ = try await CachedHTTPClient(upstream: secondUpstream, cache: secondCache).data(for: request)
        let secondRequestCount = await secondUpstream.requestCount

        XCTAssertEqual(secondRequestCount, 1)
    }

    func testHTTPResponseCacheReleaseMemoryPreservesDiskFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCacheMemory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )
        let url = URL(string: "https://example.com/api/v1/cars")!
        let response = try await CachedHTTPClient(
            upstream: CountingHTTPClient(),
            cache: cache
        ).data(for: URLRequest(url: url))

        await cache.releaseMemory()
        var offlineRequest = URLRequest(url: url)
        offlineRequest.cachePolicy = .returnCacheDataDontLoad
        let restored = try await CachedHTTPClient(
            upstream: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)),
            cache: cache
        ).data(for: offlineRequest)

        XCTAssertEqual(restored.0, response.0)
    }

    func testHTTPResponseCacheCancelsOnlyInFlightRequestsAndKeepsCompletedResponses() async throws {
        let cache = HTTPResponseCache(refreshAfter: 60)
        let cachedURL = URL(string: "https://example.com/api/v1/cars")!
        let cachedRequest = URLRequest(url: cachedURL)
        let cachedClient = CachedHTTPClient(upstream: CountingHTTPClient(), cache: cache)
        let cachedResponse = try await cachedClient.data(for: cachedRequest)

        let slowUpstream = CountingHTTPClient(delay: .seconds(30))
        let slowClient = CachedHTTPClient(upstream: slowUpstream, cache: cache)
        let slowRequest = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/drives?show=50000")!)
        let slowTask = Task { try await slowClient.data(for: slowRequest) }
        for _ in 0 ..< 100 where await slowUpstream.requestCount == 0 {
            await Task.yield()
        }

        await cache.cancelInFlightRequests()

        do {
            _ = try await slowTask.value
            XCTFail("Expected the in-flight request to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let restoredResponse = try await CachedHTTPClient(
            upstream: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)),
            cache: cache
        ).data(for: cachedRequest)
        XCTAssertEqual(restoredResponse.0, cachedResponse.0)
    }

    func testPersistentResponseCacheDoesNotWriteAuthorizationHeaderInPlaintext() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCacheSecret-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )
        let client = CachedHTTPClient(upstream: CountingHTTPClient(), cache: cache)
        var request = URLRequest(url: URL(string: "https://example.com/api/v1/cars/1/drives")!)
        request.setValue("Bearer top-secret-token", forHTTPHeaderField: "Authorization")

        _ = try await client.data(for: request)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let persistedBytes = try files.reduce(into: Data()) { data, url in
            data.append(try Data(contentsOf: url))
            data.append(Data(url.lastPathComponent.utf8))
        }
        XCTAssertFalse(String(decoding: persistedBytes, as: UTF8.self).contains("top-secret-token"))
    }

    func testPersistentResponseCacheRedactsSensitiveResponseMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveDiskCacheResponseSecret-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HTTPResponseCache(
            refreshAfter: 60,
            diskStore: FileHTTPResponseDiskStore(directory: directory)
        )
        let request = URLRequest(url: URL(string: "https://example.com/api/v1/cars?cursor=private-cursor")!)
        let client = CachedHTTPClient(
            upstream: SensitiveMetadataHTTPClient(),
            cache: cache
        )

        _ = try await client.data(for: request)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let persistedBytes = try files.reduce(into: Data()) { data, url in
            data.append(try Data(contentsOf: url))
        }
        let persisted = String(decoding: persistedBytes, as: UTF8.self)
        for secret in ["private-cookie", "private-ticket", "private-cursor", "redirect-token"] {
            XCTAssertFalse(persisted.contains(secret), "Disk cache leaked \(secret)")
        }
    }

    func testTeslamateAPIMapsCancelledURLRequestToCancellation() async {
        let api = TeslamateAPI(
            baseURL: URL(string: "https://example.com")!,
            client: ThrowingHTTPClient(error: URLError(.cancelled))
        )

        switch await api.cars() {
        case .success:
            XCTFail("Expected cancellation")
        case let .failure(error):
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testSettingsBackedFactoryLoadsAKSKSecrets() async throws {
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .apiKeys
            )),
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
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .bearerToken,
                usesCloudflareAccess: true
            )),
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

    func testCurrentChargeLiveRefreshBypassesFreshResponseCache() async throws {
        let client = RequestRecordingHTTPClient(json: #"{"data":null}"#)
        let api = TeslamateAPI(baseURL: URL(string: "https://example.com")!, client: client)

        _ = await api.refreshCurrentCharge(carId: 1)

        let recordedRequest = await client.recordedRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testFullSyncRefreshEndpointsBypassFreshResponseCache() async throws {
        let cases: [(String, @Sendable (TeslamateAPI) async -> Void)] = [
            ("activities", { _ = await $0.refreshActivities(carId: 1, page: 1, show: 200) }),
            ("drives", { _ = await $0.refreshDrives(carId: 1, page: 1, show: 50_000) }),
            ("charges", { _ = await $0.refreshCharges(carId: 1, page: 1, show: 50_000) }),
            ("battery health", { _ = await $0.refreshBatteryHealth(carId: 1) }),
            ("battery history", { _ = await $0.refreshBatteryHistory(carId: 1) })
        ]

        for (name, operation) in cases {
            let client = RequestRecordingHTTPClient(json: #"{"data":{}}"#)
            let api = TeslamateAPI(baseURL: URL(string: "https://example.com")!, client: client)

            await operation(api)

            let recordedRequest = await client.recordedRequest
            let request = try XCTUnwrap(recordedRequest, name)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, name)
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
            return XCTFail("Expected state history response, got \(result)")
        }
        XCTAssertTrue(intervals.isEmpty)
        let requestedURL = await client.requestedURL
        let url = try XCTUnwrap(requestedURL)
        XCTAssertEqual(url.path, "/base/api/v1/cars/7/states")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
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

    func testSettingsBackedFactoryIgnoresInvalidCertificatePreferenceForRemoteHTTPS() async throws {
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(
                serverURL: " https://teslamate.example ",
                authenticationMode: .automatic,
                acceptInvalidCerts: true
            )
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
            let cachedClient = try XCTUnwrap(api.client as? CachedHTTPClient)
            let client = try XCTUnwrap(cachedClient.upstream as? URLSessionHTTPClient)
            XCTAssertFalse(client.acceptsInvalidCertificates)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testSettingsBackedFactoryAppliesInvalidCertificatePreferenceForPrivateHTTPS() async throws {
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "https://192.168.3.82:3030",
                authenticationMode: .none,
                acceptInvalidCerts: true
            )),
            secretStore: InMemoryAPISecretStore(values: [:])
        )

        switch await factory.makeAPI() {
        case let .success(api):
            let cachedClient = try XCTUnwrap(api.client as? CachedHTTPClient)
            let client = try XCTUnwrap(cachedClient.upstream as? URLSessionHTTPClient)
            XCTAssertTrue(client.acceptsInvalidCertificates)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testSettingsBackedFactoryKeepsCertificateValidationByDefaultAndIgnoresBlankBasicAuth() async throws {
        let settingsStore = InMemoryAPISettingsStore(
            settings: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .bearerToken,
                acceptInvalidCerts: false
            )
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
            let cachedClient = try XCTUnwrap(api.client as? CachedHTTPClient)
            let client = try XCTUnwrap(cachedClient.upstream as? URLSessionHTTPClient)
            XCTAssertFalse(client.acceptsInvalidCertificates)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testServerURLPolicyRequiresHTTPSOnlyForRemoteHosts() {
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("https://review.example"), .secureRemote)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("http://192.168.3.82:3030"), .localHTTP)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("http://100.100.20.30:3030"), .localHTTP)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("http://teslamate.local:3030"), .localHTTP)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("http://teslamate:3030"), .localHTTP)
        XCTAssertTrue(TeslaMateServerURLPolicy.isLocalNetworkHost("http://youyooodemac-mini.local:3030"))
        XCTAssertTrue(TeslaMateServerURLPolicy.isTailscaleHost("https://youyooomac-mini.tail8e46b1.ts.net"))
        XCTAssertFalse(TeslaMateServerURLPolicy.isTailscaleHost("https://review.example"))
        XCTAssertEqual(
            TeslaMateServerURLPolicy.evaluate("http://youyooomac-mini.tail8e46b1.ts.net:3030"),
            .localHTTP
        )
        XCTAssertTrue(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://192.168.3.82:3030"))
        XCTAssertTrue(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://teslamate.local"))
        XCTAssertTrue(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://host.tail8e46b1.ts.net"))
        XCTAssertFalse(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://review.example"))
        XCTAssertFalse(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("http://192.168.3.82:3030"))
        XCTAssertEqual(
            TeslaMateServerURLPolicy.evaluate("http://review.example:3030"),
            .insecureRemoteHTTP
        )
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("ftp://review.example"), .invalid)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("https://ui-test.invalid"), .invalid)
        XCTAssertFalse(TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://ui-test.invalid"))
        let credentialedURL = "https://user" + ":password@review.example"
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate(credentialedURL), .invalid)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("https://review.example?token=secret"), .invalid)
        XCTAssertEqual(TeslaMateServerURLPolicy.evaluate("https://review.example#secret"), .invalid)
        XCTAssertTrue(TeslaMateServerURLPolicy.containsEmbeddedSecrets("https://user@review.example"))
        XCTAssertFalse(TeslaMateServerURLPolicy.containsEmbeddedSecrets("https://review.example/teslamate"))
    }

    func testServerURLPolicyDoesNotTreatDNSNamesStartingLikePrivateIPv6AsLocal() {
        for host in ["fc-attacker.example", "fd-attacker.example"] {
            XCTAssertEqual(
                TeslaMateServerURLPolicy.evaluate("http://\(host):3030"),
                .insecureRemoteHTTP,
                host
            )
            XCTAssertFalse(
                TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://\(host)"),
                host
            )
        }
        XCTAssertEqual(
            TeslaMateServerURLPolicy.evaluate("http://[fc00::1]:3030"),
            .localHTTP
        )
        XCTAssertTrue(
            TeslaMateServerURLPolicy.permitsInvalidCertificateBypass("https://[fc00::1]:3030")
        )
    }

    func testRedirectPolicyNeverSendsCredentialsAcrossOriginsOrHttpsDowngrades() throws {
        let secure = try XCTUnwrap(URL(string: "https://teslamate.example/api/v1/cars"))

        XCTAssertTrue(HTTPRedirectPolicy.allowsRedirect(
            from: secure,
            to: URL(string: "https://teslamate.example/api/v1/cars/")
        ))
        XCTAssertTrue(HTTPRedirectPolicy.allowsRedirect(
            from: URL(string: "http://teslamate.example/api"),
            to: URL(string: "https://teslamate.example/api")
        ))
        XCTAssertTrue(HTTPRedirectPolicy.allowsRedirect(
            from: URL(string: "http://teslamate.example:3030/api"),
            to: URL(string: "https://teslamate.example:3030/api")
        ))
        XCTAssertFalse(HTTPRedirectPolicy.allowsRedirect(
            from: secure,
            to: URL(string: "https://attacker.example/capture")
        ))
        XCTAssertFalse(HTTPRedirectPolicy.allowsRedirect(
            from: secure,
            to: URL(string: "http://teslamate.example/api")
        ))
        XCTAssertFalse(HTTPRedirectPolicy.allowsRedirect(
            from: URL(string: "https://teslamate.example:3030/api"),
            to: URL(string: "https://teslamate.example:3040/api")
        ))
        XCTAssertFalse(HTTPRedirectPolicy.allowsRedirect(from: nil, to: secure))
    }

    func testSettingsBackedFactoryRejectsRemotePlainHTTPBeforeRequestingSecrets() async {
        let secretStore = InMemoryAPISecretStore(values: ["apiToken": "must-not-be-read"])
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "http://review.example:3030",
                authenticationMode: .bearerToken
            )),
            secretStore: secretStore
        )

        let result = await factory.makeAPI()
        switch result {
        case .success:
            XCTFail("Expected remote plain HTTP to be rejected")
        case let .failure(error):
            XCTAssertEqual(error, .invalidURL("http://review.example:3030"))
        }
        let requestedKeys = await secretStore.requestedKeys()
        XCTAssertEqual(requestedKeys, [])
    }

    func testSettingsBackedFactoryDoesNotEchoEmbeddedURLSecretsInErrors() async {
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "https://alice" + ":secret-password@example.com?token=secret-token"
            )),
            secretStore: InMemoryAPISecretStore(values: [:])
        )

        let result = await factory.makeAPI()

        switch result {
        case .success:
            XCTFail("Expected embedded credentials to be rejected")
        case let .failure(error):
            XCTAssertEqual(error, APIError.invalidURL("[redacted]"))
        }
    }

    func testSettingsBackedFactoryOnlyUsesSelectedAuthenticationMode() async throws {
        let settingsStore = InMemoryAPISettingsStore(settings: AppSettings(
            serverURL: "https://teslamate.example",
            authenticationMode: .bearerToken
        ))
        let secretStore = InMemoryAPISecretStore(values: [
            "apiToken": "token-123",
            "httpBasicAuthUsername": "alice",
            "httpBasicAuthPassword": "secret",
            "apiAccessKey": "access-key",
            "apiSecretKey": "secret-key",
            "cloudflareAccessClientID": "cf-id",
            "cloudflareAccessClientSecret": "cf-secret"
        ])
        let factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)

        switch await factory.makeAPI() {
        case let .success(api):
            XCTAssertEqual(api.authenticator.bearerToken, "token-123")
            XCTAssertNil(api.authenticator.basicAuth)
            XCTAssertNil(api.authenticator.aksk)
            XCTAssertNil(api.authenticator.cloudflareAccess)
        case let .failure(error):
            XCTFail("Expected API, got \(error)")
        }
    }

    func testBearerAuthenticationOnlyReadsRequiredSecrets() async throws {
        let secretStore = InMemoryAPISecretStore(values: [
            "apiToken": "token-123",
            "httpBasicAuthUsername": "alice",
            "httpBasicAuthPassword": "secret",
            "apiAccessKey": "access-key",
            "apiSecretKey": "secret-key",
            "cloudflareAccessClientID": "cf-id",
            "cloudflareAccessClientSecret": "cf-secret"
        ])
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: InMemoryAPISettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .bearerToken
            )),
            secretStore: secretStore
        )

        _ = await factory.makeAPI()

        let requestedKeys = await secretStore.requestedKeys()
        XCTAssertEqual(requestedKeys, ["apiToken"])
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

    func testOpenMeteoUsesNearestHistoricalHourForDriveTimestamp() async throws {
        let coordinate = SyntheticCoordinates.point()
        let client = URLRecordingHTTPClient(
            json: #"{"hourly":{"time":[1767254400,1767258000,1767261600],"temperature_2m":[5.0,6.5,8.0],"weather_code":[3,2,1]}}"#
        )
        let api = OpenMeteoAPI(
            historicalBaseURL: URL(string: "https://historical.example")!,
            client: client
        )

        let result = await api.weather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: "2026-01-01T08:25:00Z"
        )

        guard case let .success(point) = result else {
            return XCTFail("Expected historical weather point")
        }
        XCTAssertEqual(point.temperatureCelsius, 5.0)
        XCTAssertEqual(point.weatherCode, 3)

        let requestedURL = await client.requestedURL
        XCTAssertEqual(requestedURL?.host, "historical.example")
        let components = try XCTUnwrap(requestedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["start_date"], "2026-01-01")
        XCTAssertEqual(query["end_date"], "2026-01-01")
        XCTAssertEqual(
            query["hourly"],
            "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,visibility"
        )
        XCTAssertEqual(query["timeformat"], "unixtime")
        XCTAssertEqual(query["timezone"], "GMT")
    }

    func testOpenMeteoUsesCurrentForecastWhenDriveTimestampIsMissing() async {
        let coordinate = SyntheticCoordinates.point()
        let client = URLRecordingHTTPClient(
            json: #"{"current":{"temperature_2m":31.5,"weather_code":1}}"#
        )
        let api = OpenMeteoAPI(baseURL: URL(string: "https://forecast.example")!, client: client)

        let result = await api.weather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: nil
        )

        guard case let .success(point) = result else {
            return XCTFail("Expected current weather point")
        }
        XCTAssertEqual(point.temperatureCelsius, 31.5)
        let requestedHost = await client.requestedURL?.host
        XCTAssertEqual(requestedHost, "forecast.example")
    }
}

private struct ThrowingHTTPClient: HTTPClient {
    let error: any Error & Sendable

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

private actor CountingHTTPClient: HTTPClient {
    private(set) var requestCount = 0
    private let delay: Duration?

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
        let url = request.url ?? URL(string: "https://example.com")!
        return (
            Data(#"{"data":{"cars":[]}}"#.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private struct SensitiveMetadataHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responseURL = URL(string: "https://example.com/api/v1/cars/redirect-token?ticket=private-ticket")!
        return (
            Data(#"{"data":{"cars":[]}}"#.utf8),
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "session=private-cookie",
                    "Location": "https://example.com?ticket=private-ticket"
                ]
            )!
        )
    }
}

private final class LockedDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var value: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private actor AsyncRequestGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

private actor GatedHTTPClient: HTTPClient {
    private(set) var requestCount = 0
    private let gate: AsyncRequestGate

    init(gate: AsyncRequestGate) {
        self.gate = gate
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        await gate.wait()
        let url = request.url ?? URL(string: "https://example.com")!
        return (
            Data(#"{"data":{"cars":[]}}"#.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }
}

private actor CompletionFlag {
    private(set) var isCompleted = false
    func markCompleted() { isCompleted = true }
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
    let cachePolicy: URLRequest.CachePolicy
}

private actor RequestRecorder {
    private(set) var request: RecordedHTTPRequest?

    func record(_ request: URLRequest) {
        self.request = RecordedHTTPRequest(
            url: request.url ?? URL(string: "https://example.com")!,
            method: request.httpMethod,
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: request.httpBody,
            contentHash: request.value(forHTTPHeaderField: "X-API-Content-SHA256"),
            cachePolicy: request.cachePolicy
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

private actor InMemoryAPISecretStore: SecretStoring {
    private let values: [String: String]
    private var keys: [String] = []

    init(values: [String: String]) {
        self.values = values
    }

    func get(_ key: String) async throws -> String? {
        keys.append(key)
        return values[key]
    }

    func requestedKeys() -> [String] {
        keys
    }

    func set(_: String, for _: String) async throws {}

    func remove(_: String) async throws {}
}
