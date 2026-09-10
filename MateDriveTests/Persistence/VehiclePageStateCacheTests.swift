import XCTest
@testable import MateDriveApp

final class VehiclePageStateCacheTests: XCTestCase {
    func testSeparatesVehiclesAndServersAndEvictsLeastRecentlyUsedEntry() {
        let cache = VehiclePageStateCache<String>(maximumEntryCount: 2)
        let first = VehiclePageCacheKey(serverURL: " HTTPS://One.Example/ ", carId: 1)
        let second = VehiclePageCacheKey(serverURL: "https://one.example/", carId: 2)
        let otherServer = VehiclePageCacheKey(serverURL: "https://two.example/", carId: 1)

        cache.save("first", for: first)
        cache.save("second", for: second)

        XCTAssertEqual(cache.state(for: first), "first")
        XCTAssertNil(cache.state(for: otherServer))

        cache.save("third", for: otherServer)

        XCTAssertEqual(cache.state(for: first), "first")
        XCTAssertNil(cache.state(for: second))
        XCTAssertEqual(cache.state(for: otherServer), "third")
    }

    func testSeparatesPageScopesForSameServerAndVehicle() {
        let cache = VehiclePageStateCache<String>()
        let countries2026 = VehiclePageCacheKey(
            serverURL: "https://example.invalid",
            carId: 1,
            scope: " Countries:2026 "
        )
        let countries2025 = VehiclePageCacheKey(
            serverURL: "https://example.invalid",
            carId: 1,
            scope: "countries:2025"
        )
        let regions2026 = VehiclePageCacheKey(
            serverURL: "https://example.invalid",
            carId: 1,
            scope: "regions:cn:2026"
        )

        cache.save("countries-2026", for: countries2026)
        cache.save("countries-2025", for: countries2025)
        cache.save("regions-2026", for: regions2026)

        XCTAssertEqual(
            cache.state(for: VehiclePageCacheKey(
                serverURL: "HTTPS://EXAMPLE.INVALID",
                carId: 1,
                scope: "countries:2026"
            )),
            "countries-2026"
        )
        XCTAssertEqual(cache.state(for: countries2025), "countries-2025")
        XCTAssertEqual(cache.state(for: regions2026), "regions-2026")
    }

    func testRemoveInvalidatesOnlyRequestedEntry() {
        let cache = VehiclePageStateCache<String>()
        let first = VehiclePageCacheKey(serverURL: "https://one.example.com", carId: 1)
        let second = VehiclePageCacheKey(serverURL: "https://one.example.com", carId: 2)
        cache.save("first", for: first)
        cache.save("second", for: second)

        cache.remove(for: first)

        XCTAssertNil(cache.state(for: first))
        XCTAssertEqual(cache.state(for: second), "second")
    }

    func testRegistryReleasesEveryLivePageCache() {
        let first = VehiclePageStateCache<String>()
        let second = VehiclePageStateCache<Int>()
        let firstKey = VehiclePageCacheKey(serverURL: "https://one.example.com", carId: 1)
        let secondKey = VehiclePageCacheKey(serverURL: "https://two.example.com", carId: 2)
        first.save("cached", for: firstKey)
        second.save(42, for: secondKey)

        VehiclePageStateCacheRegistry.releaseMemory()

        XCTAssertNil(first.state(for: firstKey))
        XCTAssertNil(second.state(for: secondKey))
    }
}
