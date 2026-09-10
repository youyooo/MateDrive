import Foundation
import XCTest
@testable import MateDriveApp

final class WeatherServiceTests: XCTestCase {
    func testDriveEnvironmentRequestsOnlyTheTemporalMidpointSample() async throws {
        let api = FakeWeatherAPI(results: [.success(.fixture(temperatureCelsius: 21))])
        let service = WeatherService(api: api, cache: WeatherCache(storageURL: nil))
        let first = SyntheticCoordinates.point()
        let middle = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let last = SyntheticCoordinates.point(latitudeOffset: 0.2, longitudeOffset: 0.2)
        let positions = [
            WeatherRoutePosition(latitude: first.latitude, longitude: first.longitude, date: "2026-07-18T08:00:00Z"),
            WeatherRoutePosition(latitude: middle.latitude, longitude: middle.longitude, date: "2026-07-18T09:00:00Z"),
            WeatherRoutePosition(latitude: last.latitude, longitude: last.longitude, date: "2026-07-18T10:00:00Z")
        ]

        let point = await service.drivingEnvironment(positions: positions)

        XCTAssertEqual(point?.temperatureCelsius, 21)
        let requests = await api.requestsSnapshot()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.latitude, middle.latitude)
        XCTAssertEqual(requests.first?.longitude, middle.longitude)
        XCTAssertEqual(requests.first?.date, "2026-07-18T09:00:00Z")
    }

    func testSuccessfulWeatherPersistsAcrossServiceInstances() async throws {
        let storageURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let coordinate = SyntheticCoordinates.point()
        let positions = [
            WeatherRoutePosition(latitude: coordinate.latitude, longitude: coordinate.longitude, date: "2026-07-18T09:15:00Z")
        ]
        let firstAPI = FakeWeatherAPI(results: [.success(.fixture(temperatureCelsius: 19))])
        let firstService = WeatherService(api: firstAPI, cache: WeatherCache(storageURL: storageURL))

        let first = await firstService.drivingEnvironment(positions: positions)

        let secondAPI = FakeWeatherAPI(results: [])
        let secondService = WeatherService(api: secondAPI, cache: WeatherCache(storageURL: storageURL))
        let second = await secondService.drivingEnvironment(positions: positions)

        XCTAssertEqual(first, second)
        let firstRequestCount = await firstAPI.requestCount()
        let secondRequestCount = await secondAPI.requestCount()
        XCTAssertEqual(firstRequestCount, 1)
        XCTAssertEqual(secondRequestCount, 0)
    }

    func testWeatherCacheReleaseMemoryPreservesDiskFallback() async throws {
        let storageURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent()) }
        let coordinate = SyntheticCoordinates.point()
        let key = try XCTUnwrap(WeatherCacheKey(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: "2026-07-18T09:15:00Z"
        ))
        let point = WeatherPoint.fixture(temperatureCelsius: 23)
        let cache = WeatherCache(storageURL: storageURL)
        await cache.save(point, for: key)

        await cache.releaseMemory()
        let restored = await cache.load(key)

        XCTAssertEqual(restored, point)
    }

    func testFailedWeatherIsNotCached() async {
        let api = FakeWeatherAPI(results: [
            .failure(.network("offline")),
            .success(.fixture(temperatureCelsius: 18))
        ])
        let service = WeatherService(api: api, cache: WeatherCache(storageURL: nil))
        let coordinate = SyntheticCoordinates.point()
        let positions = [
            WeatherRoutePosition(latitude: coordinate.latitude, longitude: coordinate.longitude, date: "2026-07-18T09:15:00Z")
        ]

        let first = await service.drivingEnvironment(positions: positions)
        let second = await service.drivingEnvironment(positions: positions)

        XCTAssertNil(first)
        XCTAssertEqual(second?.temperatureCelsius, 18)
        let requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testConcurrentIdenticalWeatherRequestsAreCoalesced() async {
        let api = FakeWeatherAPI(results: [.success(.fixture())], delayNanoseconds: 100_000_000)
        let service = WeatherService(api: api, cache: WeatherCache(storageURL: nil))
        let coordinate = SyntheticCoordinates.point()
        let positions = [
            WeatherRoutePosition(latitude: coordinate.latitude, longitude: coordinate.longitude, date: "2026-07-18T09:15:00Z")
        ]

        async let first = service.drivingEnvironment(positions: positions)
        async let second = service.drivingEnvironment(positions: positions)
        let results = await [first, second]

        XCTAssertEqual(results[0], results[1])
        let requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testDriveEnvironmentReturnsNilWithoutValidHistoricalPosition() async {
        let api = FakeWeatherAPI(results: [.success(.fixture())])
        let service = WeatherService(api: api, cache: WeatherCache(storageURL: nil))

        let coordinate = SyntheticCoordinates.point()
        let point = await service.drivingEnvironment(positions: [
            WeatherRoutePosition(latitude: coordinate.latitude, longitude: coordinate.longitude, date: nil)
        ])

        XCTAssertNil(point)
        let requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MateDriveWeatherTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("weather-cache.json", isDirectory: false)
    }
}

private actor FakeWeatherAPI: WeatherAPIProviding {
    struct Request: Equatable {
        let latitude: Double
        let longitude: Double
        let date: String?
    }

    private var results: [APIResult<WeatherPoint>]
    private var requests: [Request] = []
    private let delayNanoseconds: UInt64

    init(results: [APIResult<WeatherPoint>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func weather(latitude: Double, longitude: Double, date: String?) async -> APIResult<WeatherPoint> {
        requests.append(Request(latitude: latitude, longitude: longitude, date: date))
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !results.isEmpty else { return .failure(.emptyBody) }
        return results.removeFirst()
    }

    func requestsSnapshot() -> [Request] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}

private extension WeatherPoint {
    static func fixture(temperatureCelsius: Double = 20) -> WeatherPoint {
        let coordinate = SyntheticCoordinates.point()
        return WeatherPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            temperatureCelsius: temperatureCelsius,
            weatherCode: 1
        )
    }
}
